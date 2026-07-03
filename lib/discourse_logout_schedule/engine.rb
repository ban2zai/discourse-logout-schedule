# frozen_string_literal: true

module ::DiscourseLogoutSchedule
  class Engine < ::Rails::Engine
    engine_name "discourse_logout_schedule"
    isolate_namespace DiscourseLogoutSchedule
  end
end
