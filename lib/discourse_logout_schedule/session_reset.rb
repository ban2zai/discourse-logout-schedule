# frozen_string_literal: true

module ::DiscourseLogoutSchedule
  class SessionReset
    LAST_RUN_KEY = "last_run_key"
    MUTEX_KEY = "discourse_logout_schedule:session_reset"
    DAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze
    TIME_PATTERN = /\A([01]?\d|2[0-3]):([0-5]\d)\z/

    Result = Struct.new(
      :status,
      :dry_run,
      :run_key,
      :token_count,
      :affected_user_count,
      :deleted_token_count,
      :excluded_users,
      :excluded_groups,
      :message,
      keyword_init: true,
    ) do
      def to_h
        {
          status: status,
          dry_run: dry_run,
          run_key: run_key,
          tokens_matched: token_count || 0,
          affected_users: affected_user_count || 0,
          tokens_deleted: deleted_token_count || 0,
          excluded_users: excluded_users || [],
          excluded_groups: excluded_groups || [],
          message: message,
        }
      end
    end

    def initialize(force: false)
      @force = force
    end

    def run
      with_mutex do
        schedule = schedule_state
        return skipped(schedule[:message]) unless force || schedule[:due]

        result = reset_sessions(run_key: schedule[:run_key])
        mark_run(schedule[:run_key]) if !force && result.status == :ok
        log_result(result)
        result
      end
    end

    private

    attr_reader :force

    def schedule_state
      zone = Time.find_zone(SiteSetting.discourse_logout_schedule_timezone)
      return invalid("invalid timezone: #{SiteSetting.discourse_logout_schedule_timezone.inspect}") if zone.blank?

      time = parse_time(SiteSetting.discourse_logout_schedule_time)
      return invalid("invalid time: #{SiteSetting.discourse_logout_schedule_time.inspect}") if time.blank?

      day = SiteSetting.discourse_logout_schedule_day_of_week.to_s.downcase
      return invalid("invalid day_of_week: #{day.inspect}") if DAYS.exclude?(day)

      now = zone.now
      run_key = "#{now.to_date.iso8601}:#{day}:#{format('%02d:%02d', time[:hour], time[:minute])}:#{zone.tzinfo.name}"
      due =
        now.strftime("%A").downcase == day &&
          (now.hour > time[:hour] || (now.hour == time[:hour] && now.min >= time[:minute]))

      if due && PluginStore.get(PLUGIN_NAME, LAST_RUN_KEY) == run_key
        return { due: false, run_key: run_key, message: "already ran for #{run_key}" }
      end

      { due: due, run_key: run_key, message: due ? "due" : "not due" }
    end

    def invalid(message)
      log_warn(message)
      { due: false, run_key: nil, message: message }
    end

    def parse_time(value)
      match = TIME_PATTERN.match(value.to_s.strip)
      return if match.blank?

      { hour: match[1].to_i, minute: match[2].to_i }
    end

    def reset_sessions(run_key:)
      exclusions = Exclusions.new
      target_tokens = UserAuthToken.where.not(user_id: exclusions.user_ids.to_a)
      token_count = target_tokens.count
      affected_user_count = target_tokens.distinct.count(:user_id)
      deleted_token_count = dry_run? ? 0 : target_tokens.delete_all

      Result.new(
        status: :ok,
        dry_run: dry_run?,
        run_key: run_key,
        token_count: token_count,
        affected_user_count: affected_user_count,
        deleted_token_count: deleted_token_count,
        excluded_users: exclusions.excluded_users,
        excluded_groups: exclusions.configured_groups,
        message: "session reset completed",
      )
    end

    def dry_run?
      SiteSetting.discourse_logout_schedule_dry_run?
    end

    def mark_run(run_key)
      PluginStore.set(PLUGIN_NAME, LAST_RUN_KEY, run_key) if run_key.present?
    end

    def skipped(message)
      result = Result.new(status: :skipped, dry_run: dry_run?, message: message)
      log_result(result)
      result
    end

    def with_mutex(&block)
      if defined?(::DistributedMutex)
        ::DistributedMutex.synchronize(MUTEX_KEY, &block)
      else
        yield
      end
    end

    def log_result(result)
      return unless SiteSetting.discourse_logout_schedule_log_result?

      logger.info(
        "[#{PLUGIN_NAME}] status=#{result.status} dry_run=#{result.dry_run} run_key=#{result.run_key.inspect} " \
          "tokens_matched=#{result.token_count || 0} affected_users=#{result.affected_user_count || 0} " \
          "tokens_deleted=#{result.deleted_token_count || 0} excluded_groups=#{result.excluded_groups.inspect} " \
          "excluded_users=#{result.excluded_users.inspect} message=#{result.message.inspect}",
      )
    end

    def log_warn(message)
      logger.warn("[#{PLUGIN_NAME}] #{message}")
    end

    def logger
      Rails.logger
    end
  end
end
