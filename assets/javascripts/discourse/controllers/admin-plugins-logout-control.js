import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

export default class AdminPluginsLogoutControlController extends Controller {
  @tracked enabled = false;
  @tracked dryRun = true;
  @tracked loading = false;
  @tracked working = false;
  @tracked page = 1;
  @tracked perPage = 50;
  @tracked totalUsers = 0;
  @tracked hasNextPage = false;
  @tracked username = "";
  @tracked summary = null;
  @tracked users = [];
  @tracked notice = null;

  setData(data) {
    this.enabled = data.enabled;
    this.dryRun = data.dry_run;
    this.page = data.page;
    this.perPage = data.per_page;
    this.totalUsers = data.total_users;
    this.hasNextPage = data.has_next_page;
    this.summary = data.summary;
    this.users = data.users || [];
  }

  async loadPage(page = this.page) {
    this.loading = true;

    try {
      const data = await ajax("/admin/plugins/logout-control.json", {
        data: {
          page,
          per_page: this.perPage,
          username: this.username,
        },
      });

      this.setData(data);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.loading = false;
    }
  }

  @action
  refresh() {
    this.notice = null;
    return this.loadPage(this.page);
  }

  @action
  search() {
    this.notice = null;
    return this.loadPage(1);
  }

  @action
  previousPage() {
    if (this.page <= 1) {
      return;
    }

    return this.loadPage(this.page - 1);
  }

  @action
  nextPage() {
    if (!this.hasNextPage) {
      return;
    }

    return this.loadPage(this.page + 1);
  }

  @action
  async logoutAll() {
    this.working = true;
    this.notice = null;

    try {
      const result = await ajax("/admin/plugins/logout-control/logout-all.json", {
        type: "POST",
      });

      this.notice = this.resultText(result);
      await this.loadPage(this.page);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.working = false;
    }
  }

  @action
  async logoutUser(user) {
    if (user.excluded) {
      return;
    }

    this.working = true;
    this.notice = null;

    try {
      const result = await ajax(
        `/admin/plugins/logout-control/users/${user.user_id}/logout.json`,
        { type: "POST" }
      );

      this.notice = this.resultText(result);
      await this.loadPage(this.page);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.working = false;
    }
  }

  resultText(result) {
    if (result.dry_run) {
      return i18n("logout_control.notices.dry_run", {
        tokens: result.tokens_matched,
        users: result.affected_users,
      });
    }

    return i18n("logout_control.notices.completed", {
      tokens: result.tokens_deleted,
      users: result.affected_users,
    });
  }
}
