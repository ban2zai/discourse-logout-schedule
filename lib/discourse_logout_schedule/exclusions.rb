# frozen_string_literal: true

require "set"

module ::DiscourseLogoutSchedule
  class Exclusions
    SPECIAL_GROUPS = %w[admins moderators staff].freeze

    def initialize
      @user_ids = Set.new
      @reasons_by_user_id = Hash.new { |hash, key| hash[key] = Set.new }
      build!
    end

    attr_reader :user_ids, :configured_groups

    def excluded?(user_id)
      user_ids.include?(user_id.to_i)
    end

    def reasons_for(user_id)
      @reasons_by_user_id[user_id.to_i].to_a.sort
    end

    def reason_text_for(user_id)
      reasons_for(user_id).join(", ")
    end

    def excluded_users
      User.where(id: user_ids.to_a).order(:username).pluck(:id, :username)
    end

    private

    def build!
      @configured_groups = list_setting(SiteSetting.discourse_logout_schedule_excluded_groups).map(&:downcase)
      explicit_usernames = list_setting(SiteSetting.discourse_logout_schedule_excluded_usernames).map(&:downcase)

      add_admins(reason: "admin")
      add_explicit_users(explicit_usernames)
      add_special_groups(configured_groups)
      add_regular_groups(configured_groups - SPECIAL_GROUPS)
    end

    def add_admins(reason:)
      User.where(admin: true).pluck(:id).each { |user_id| add_user(user_id, reason) }
    end

    def add_explicit_users(usernames)
      return if usernames.blank?

      User.where("LOWER(username) IN (?)", usernames).pluck(:id).each do |user_id|
        add_user(user_id, "excluded username")
      end
    end

    def add_special_groups(group_names)
      add_admins(reason: "group: admins") if group_names.include?("admins")

      if group_names.include?("moderators")
        User.where(moderator: true).pluck(:id).each { |user_id| add_user(user_id, "group: moderators") }
      end

      return if !group_names.include?("staff")

      User.where(admin: true).or(User.where(moderator: true)).pluck(:id).each do |user_id|
        add_user(user_id, "group: staff")
      end
    end

    def add_regular_groups(group_names)
      return if group_names.blank?

      Group.where("LOWER(name) IN (?)", group_names).find_each do |group|
        GroupUser.where(group_id: group.id).pluck(:user_id).each do |user_id|
          add_user(user_id, "group: #{group.name}")
        end
      end
    end

    def add_user(user_id, reason)
      user_ids.add(user_id)
      @reasons_by_user_id[user_id].add(reason)
    end

    def list_setting(value)
      case value
      when Array
        value
      else
        value.to_s.split(/[|,\n]/)
      end.map(&:strip).reject(&:blank?)
    end
  end
end
