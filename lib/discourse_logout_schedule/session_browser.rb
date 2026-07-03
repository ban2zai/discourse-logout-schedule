# frozen_string_literal: true

module ::DiscourseLogoutSchedule
  class SessionBrowser
    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 100

    def initialize(page:, per_page:, username:)
      @page = [page.to_i, 1].max
      @per_page = [[per_page.to_i, DEFAULT_PER_PAGE].max, MAX_PER_PAGE].min
      @username = username.to_s.strip
      @exclusions = Exclusions.new
    end

    def to_h
      users = paged_users
      user_ids = users.map(&:id)
      aggregates = aggregates_for(user_ids)
      latest_tokens = latest_tokens_for(user_ids)

      {
        enabled: SiteSetting.discourse_logout_schedule_enabled?,
        dry_run: SiteSetting.discourse_logout_schedule_dry_run?,
        page: page,
        per_page: per_page,
        total_users: filtered_users_scope.count,
        has_next_page: page * per_page < filtered_users_scope.count,
        summary: summary,
        users:
          users.map do |user|
            aggregate = aggregates[user.id] || {}
            latest_token = latest_tokens[user.id]
            last_login_at = aggregate[:last_login_at]
            token_seen_at = aggregate[:last_seen_at]
            last_seen_at = token_seen_at || user.last_seen_at

            {
              user_id: user.id,
              username: user.username,
              name: user.name,
              admin: user.admin?,
              moderator: user.moderator?,
              staff: user.staff?,
              excluded: exclusions.excluded?(user.id),
              exclusion_reasons: exclusions.reasons_for(user.id),
              exclusion_reason: exclusions.reason_text_for(user.id),
              session_count: aggregate[:session_count] || 0,
              oauth_session_count: aggregate[:oauth_session_count] || 0,
              last_login_at: iso8601(last_login_at),
              last_login_age_seconds: age_seconds(last_login_at),
              last_login_age: human_age(last_login_at),
              last_seen_at: iso8601(last_seen_at),
              last_seen_age_seconds: age_seconds(last_seen_at),
              last_seen_age: human_age(last_seen_at),
              last_session_rotated_at: iso8601(aggregate[:last_session_rotated_at]),
              latest_client_ip: latest_token&.client_ip&.to_s,
              latest_user_agent: latest_token&.user_agent,
            }
          end,
      }
    end

    private

    attr_reader :page, :per_page, :username, :exclusions

    def summary
      active_user_ids = active_tokens.distinct.pluck(:user_id)
      eligible_user_ids = active_user_ids - exclusions.user_ids.to_a

      {
        active_session_count: active_tokens.count,
        active_user_count: active_user_ids.count,
        eligible_user_count: eligible_user_ids.count,
        excluded_user_count: (active_user_ids & exclusions.user_ids.to_a).count,
        excluded_groups: exclusions.configured_groups,
      }
    end

    def paged_users
      filtered_users_scope.order(:username).offset((page - 1) * per_page).limit(per_page).to_a
    end

    def filtered_users_scope
      scope = User.where(id: active_tokens.select(:user_id).distinct)
      return scope if username.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(username.downcase)}%"
      scope.where("LOWER(username) LIKE ?", pattern)
    end

    def active_tokens
      UserAuthToken.where("rotated_at > ?", SiteSetting.maximum_session_age.hours.ago)
    end

    def aggregates_for(user_ids)
      return {} if user_ids.blank?

      active_tokens
        .where(user_id: user_ids)
        .group(:user_id)
        .pluck(
          :user_id,
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(CASE WHEN authenticated_with_oauth THEN 1 ELSE 0 END)"),
          Arel.sql("MAX(created_at)"),
          Arel.sql("MAX(seen_at)"),
          Arel.sql("MAX(rotated_at)"),
        )
        .each_with_object({}) do |row, memo|
          user_id, session_count, oauth_session_count, last_login_at, last_seen_at, last_session_rotated_at = row
          memo[user_id] = {
            session_count: session_count.to_i,
            oauth_session_count: oauth_session_count.to_i,
            last_login_at: last_login_at,
            last_seen_at: last_seen_at,
            last_session_rotated_at: last_session_rotated_at,
          }
        end
    end

    def latest_tokens_for(user_ids)
      return {} if user_ids.blank?

      active_tokens
        .where(user_id: user_ids)
        .order("user_id ASC, rotated_at DESC")
        .to_a
        .group_by(&:user_id)
        .transform_values(&:first)
    end

    def iso8601(time)
      time&.iso8601
    end

    def age_seconds(time)
      return if time.blank?

      (Time.zone.now - time).to_i
    end

    def human_age(time)
      seconds = age_seconds(time)
      return if seconds.blank?

      days = seconds / 1.day
      return "#{days} дн." if days.positive?

      hours = seconds / 1.hour
      return "#{hours} ч." if hours.positive?

      minutes = seconds / 1.minute
      return "#{minutes} мин." if minutes.positive?

      "#{seconds} сек."
    end
  end
end
