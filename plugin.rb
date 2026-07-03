# frozen_string_literal: true

# name: discourse-logout-schedule
# about: Scheduled invalidation of Discourse user sessions to force fresh OIDC login.
# version: 0.1.0
# authors: ban2zai
# url: https://github.com/ban2zai/discourse-logout-schedule
# required_version: 3.0.0

enabled_site_setting :discourse_logout_schedule_enabled

module ::DiscourseLogoutSchedule
  PLUGIN_NAME = "discourse-logout-schedule"
end

after_initialize do
  require_relative "lib/discourse_logout_schedule/session_reset"
end
