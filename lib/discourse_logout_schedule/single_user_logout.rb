# frozen_string_literal: true

module ::DiscourseLogoutSchedule
  class SingleUserLogout
    def initialize(user_id:)
      @user_id = user_id.to_i
    end

    def run
      user = User.find_by(id: user_id)
      return not_found if user.blank?

      exclusions = Exclusions.new
      if exclusions.excluded?(user.id)
        return result(
                 status: :skipped,
                 token_count: 0,
                 affected_user_count: 0,
                 deleted_token_count: 0,
                 excluded_users: [[user.id, user.username]],
                 excluded_groups: exclusions.configured_groups,
                 message: "user is excluded: #{exclusions.reason_text_for(user.id)}",
               )
      end

      tokens = UserAuthToken.where(user_id: user.id)
      token_count = tokens.count
      deleted_token_count = dry_run? ? 0 : tokens.delete_all

      result(
        status: :ok,
        token_count: token_count,
        affected_user_count: token_count.positive? ? 1 : 0,
        deleted_token_count: deleted_token_count,
        excluded_users: exclusions.excluded_users,
        excluded_groups: exclusions.configured_groups,
        message: "single user logout completed",
      )
    end

    private

    attr_reader :user_id

    def not_found
      result(
        status: :not_found,
        token_count: 0,
        affected_user_count: 0,
        deleted_token_count: 0,
        excluded_users: [],
        excluded_groups: [],
        message: "user not found",
      )
    end

    def result(attributes)
      SessionReset::Result.new(
        dry_run: dry_run?,
        run_key: nil,
        **attributes,
      ).tap { |result| log_result(result) }
    end

    def dry_run?
      SiteSetting.discourse_logout_schedule_dry_run?
    end

    def log_result(result)
      return unless SiteSetting.discourse_logout_schedule_log_result?

      Rails.logger.info(
        "[#{PLUGIN_NAME}] single_user_logout status=#{result.status} dry_run=#{result.dry_run} " \
          "user_id=#{user_id} tokens_matched=#{result.token_count || 0} " \
          "tokens_deleted=#{result.deleted_token_count || 0} message=#{result.message.inspect}",
      )
    end
  end
end
