import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class AdminPluginsLogoutControlRoute extends DiscourseRoute {
  model() {
    return ajax("/admin/plugins/logout-control.json");
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.setData(model);
  }
}
