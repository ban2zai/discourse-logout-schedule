# frozen_string_literal: true

module Jobs
  class DiscourseLogoutSchedule < ::Jobs::Scheduled
    every 5.minutes

    def execute(args = {})
      return unless SiteSetting.discourse_logout_schedule_enabled?

      ::DiscourseLogoutSchedule::SessionReset.new(force: truthy?(args[:force] || args["force"])).run
    end

    private

    def truthy?(value)
      value == true || value.to_s == "true"
    end
  end
end
