# frozen_string_literal: true

module ::DiscourseLogoutSchedule
  module Admin
    class LogoutControlController < ::ApplicationController
      requires_plugin ::DiscourseLogoutSchedule::PLUGIN_NAME

      before_action :ensure_site_admin

      def index
        render json:
                 ::DiscourseLogoutSchedule::SessionBrowser.new(
                   page: params[:page],
                   per_page: params[:per_page],
                   username: params[:username],
                 ).to_h
      end

      def logout_all
        result = ::DiscourseLogoutSchedule::SessionReset.new(force: true).run
        render json: result.to_h
      end

      def logout_user
        result = ::DiscourseLogoutSchedule::SingleUserLogout.new(user_id: params[:user_id]).run
        render json: result.to_h, status: result.status == :not_found ? :not_found : :ok
      end

      private

      def ensure_site_admin
        if guardian.respond_to?(:ensure_can_admin_site!)
          guardian.ensure_can_admin_site!
        elsif !current_user&.admin?
          raise Discourse::InvalidAccess.new
        end
      end
    end
  end
end
