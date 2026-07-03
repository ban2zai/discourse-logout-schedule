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

add_admin_route "logout_control.title", "logout-control"

Discourse::Application.routes.append do
  get "/admin/plugins/logout-control" => "admin/plugins#index", constraints: StaffConstraint.new
  get "/admin/plugins/logout-control.json" => "admin/plugins/logout_control#index"
  post "/admin/plugins/logout-control/logout-all.json" => "admin/plugins/logout_control#logout_all"
  post "/admin/plugins/logout-control/users/:user_id/logout.json" => "admin/plugins/logout_control#logout_user"
end

after_initialize do
  require_relative "lib/discourse_logout_schedule/exclusions"
  require_relative "lib/discourse_logout_schedule/session_browser"
  require_relative "lib/discourse_logout_schedule/session_reset"
  require_relative "lib/discourse_logout_schedule/single_user_logout"
end
