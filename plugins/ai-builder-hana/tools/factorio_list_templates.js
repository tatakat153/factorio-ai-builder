/** 查看模板 (Planner) */
import { get } from "../lib/bridge.js";
export const name = "factorio_list_templates";
export const description = "列出所有可用的建造模板及其参数。在批量建造前应调用此工具确认模板名和所需参数。";
export const parameters = { type: "object", properties: {}, required: [] };
export async function execute(input, ctx) {
  const data = await get(ctx, "/api/v1/templates");
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
