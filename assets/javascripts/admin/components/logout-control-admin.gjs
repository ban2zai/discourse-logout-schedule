import Component from "@glimmer/component";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

export default class LogoutControlAdmin extends Component {
  @tracked enabled = false;
  @tracked dryRun = true;
  @tracked loading = true;
  @tracked working = false;
  @tracked page = 1;
  @tracked perPage = 50;
  @tracked totalUsers = 0;
  @tracked hasNextPage = false;
  @tracked username = "";
  @tracked summary = {};
  @tracked users = [];
  @tracked notice = null;
  @tracked error = null;

  constructor() {
    super(...arguments);
    this.loadPage(1);
  }

  get previousDisabled() {
    return this.loading || this.page <= 1;
  }

  get nextDisabled() {
    return this.loading || !this.hasNextPage;
  }

  get logoutAllDisabled() {
    return this.working || this.loading;
  }

  applyData(data) {
    this.enabled = data.enabled;
    this.dryRun = data.dry_run;
    this.page = data.page;
    this.perPage = data.per_page;
    this.totalUsers = data.total_users;
    this.hasNextPage = data.has_next_page;
    this.summary = data.summary || {};
    this.users = data.users || [];
  }

  async loadPage(page = this.page) {
    this.loading = true;
    this.error = null;

    try {
      const data = await ajax("/admin/plugins/logout-control.json", {
        data: {
          page,
          per_page: this.perPage,
          username: this.username,
        },
      });

      this.applyData(data);
    } catch {
      this.error = i18n("logout_control.errors.load");
    } finally {
      this.loading = false;
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

  @action
  updateUsername(event) {
    this.username = event.target.value;
  }

  @action
  refresh() {
    this.notice = null;
    this.loadPage(this.page);
  }

  @action
  search() {
    this.notice = null;
    this.loadPage(1);
  }

  @action
  previousPage() {
    if (!this.previousDisabled) {
      this.loadPage(this.page - 1);
    }
  }

  @action
  nextPage() {
    if (!this.nextDisabled) {
      this.loadPage(this.page + 1);
    }
  }

  @action
  async logoutAll() {
    this.working = true;
    this.notice = null;
    this.error = null;

    try {
      const result = await ajax("/admin/plugins/logout-control/logout-all.json", {
        type: "POST",
      });

      this.notice = this.resultText(result);
      await this.loadPage(this.page);
    } catch {
      this.error = i18n("logout_control.errors.logout");
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
    this.error = null;

    try {
      const result = await ajax(
        `/admin/plugins/logout-control/users/${user.user_id}/logout.json`,
        { type: "POST" }
      );

      this.notice = this.resultText(result);
      await this.loadPage(this.page);
    } catch {
      this.error = i18n("logout_control.errors.logout");
    } finally {
      this.working = false;
    }
  }

  <template>
    <section class="logout-control">
      <h2>{{i18n "logout_control.title"}}</h2>
      <p>{{i18n "logout_control.description"}}</p>

      {{#if this.notice}}
        <div class="alert alert-info">{{this.notice}}</div>
      {{/if}}

      {{#if this.error}}
        <div class="alert alert-error">{{this.error}}</div>
      {{/if}}

      <div class="logout-control-summary">
        <div class="logout-control-summary__item">
          <strong>{{this.summary.active_session_count}}</strong>
          <span>{{i18n "logout_control.summary.active_sessions"}}</span>
        </div>
        <div class="logout-control-summary__item">
          <strong>{{this.summary.active_user_count}}</strong>
          <span>{{i18n "logout_control.summary.active_users"}}</span>
        </div>
        <div class="logout-control-summary__item">
          <strong>{{this.summary.eligible_user_count}}</strong>
          <span>{{i18n "logout_control.summary.eligible_users"}}</span>
        </div>
        <div class="logout-control-summary__item">
          <strong>
            {{#if this.dryRun}}
              {{i18n "logout_control.summary.dry_run_on"}}
            {{else}}
              {{i18n "logout_control.summary.dry_run_off"}}
            {{/if}}
          </strong>
          <span>{{i18n "logout_control.summary.mode"}}</span>
        </div>
      </div>

      <div class="logout-control-toolbar">
        <input
          class="logout-control-toolbar__search"
          value={{this.username}}
          placeholder={{i18n "logout_control.search_placeholder"}}
          {{on "input" this.updateUsername}}
        />
        <button
          type="button"
          class="btn"
          disabled={{this.loading}}
          {{on "click" this.search}}
        >
          {{i18n "logout_control.actions.search"}}
        </button>
        <button
          type="button"
          class="btn"
          disabled={{this.loading}}
          {{on "click" this.refresh}}
        >
          {{i18n "logout_control.actions.refresh"}}
        </button>
        <button
          type="button"
          class="btn btn-danger"
          disabled={{this.logoutAllDisabled}}
          {{on "click" this.logoutAll}}
        >
          {{i18n "logout_control.actions.logout_all"}}
        </button>
      </div>

      {{#if this.loading}}
        <p>{{i18n "logout_control.loading"}}</p>
      {{else}}
        <table class="table logout-control-table">
          <thead>
            <tr>
              <th>{{i18n "logout_control.table.user"}}</th>
              <th>{{i18n "logout_control.table.sessions"}}</th>
              <th>{{i18n "logout_control.table.last_login"}}</th>
              <th>{{i18n "logout_control.table.last_seen"}}</th>
              <th>{{i18n "logout_control.table.ip"}}</th>
              <th>{{i18n "logout_control.table.exclusion"}}</th>
              <th>{{i18n "logout_control.table.action"}}</th>
            </tr>
          </thead>
          <tbody>
            {{#each this.users as |user|}}
              <tr>
                <td>
                  <a href="/admin/users/{{user.user_id}}/{{user.username}}">
                    {{user.username}}
                  </a>
                  {{#if user.name}}
                    <div class="logout-control-table__muted">{{user.name}}</div>
                  {{/if}}
                  {{#if user.staff}}
                    <span class="badge-notification">
                      {{i18n "logout_control.badges.staff"}}
                    </span>
                  {{/if}}
                </td>
                <td>
                  {{user.session_count}}
                  <div class="logout-control-table__muted">
                    {{i18n "logout_control.table.oauth_sessions" count=user.oauth_session_count}}
                  </div>
                </td>
                <td>
                  {{#if user.last_login_at}}
                    {{user.last_login_at}}
                    <div class="logout-control-table__muted">{{user.last_login_age}}</div>
                  {{else}}
                    -
                  {{/if}}
                </td>
                <td>
                  {{#if user.last_seen_at}}
                    {{user.last_seen_at}}
                    <div class="logout-control-table__muted">{{user.last_seen_age}}</div>
                  {{else}}
                    -
                  {{/if}}
                </td>
                <td>
                  {{#if user.latest_client_ip}}
                    {{user.latest_client_ip}}
                  {{else}}
                    -
                  {{/if}}
                  {{#if user.latest_user_agent}}
                    <div class="logout-control-table__muted">{{user.latest_user_agent}}</div>
                  {{/if}}
                </td>
                <td>
                  {{#if user.excluded}}
                    {{user.exclusion_reason}}
                  {{else}}
                    {{i18n "logout_control.table.not_excluded"}}
                  {{/if}}
                </td>
                <td>
                  {{#if user.excluded}}
                    <button type="button" class="btn" disabled>
                      {{i18n "logout_control.actions.excluded"}}
                    </button>
                  {{else}}
                    <button
                      type="button"
                      class="btn"
                      disabled={{this.working}}
                      {{on "click" (fn this.logoutUser user)}}
                    >
                      {{i18n "logout_control.actions.logout_user"}}
                    </button>
                  {{/if}}
                </td>
              </tr>
            {{else}}
              <tr>
                <td colspan="7">{{i18n "logout_control.table.empty"}}</td>
              </tr>
            {{/each}}
          </tbody>
        </table>

        <div class="logout-control-pagination">
          <button
            type="button"
            class="btn"
            disabled={{this.previousDisabled}}
            {{on "click" this.previousPage}}
          >
            {{i18n "logout_control.actions.previous"}}
          </button>
          <span>
            {{i18n "logout_control.pagination.page" page=this.page total=this.totalUsers}}
          </span>
          <button
            type="button"
            class="btn"
            disabled={{this.nextDisabled}}
            {{on "click" this.nextPage}}
          >
            {{i18n "logout_control.actions.next"}}
          </button>
        </div>
      {{/if}}
    </section>
  </template>
}
