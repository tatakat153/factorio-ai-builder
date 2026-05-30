/** 放入物品 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_insert_items";
export const description = "从角色背包取出物品放入机器/箱子中。inv_type 可选: input, output, fuel, chest。不指定则自动选择。";
export const parameters = {
  type: "object",
  properties: { entity_name: { type: "string" }, x: { type: "number" }, y: { type: "number" }, item_name: { type: "string" }, count: { type: "number" }, inv_type: { type: "string" } },
  required: ["entity_name", "x", "y", "item_name", "count"],
};
export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/agent/insert", { entity_name: input.entity_name, position: { x: input.x, y: input.y }, item_name: input.item_name, count: input.count, inv_type: input.inv_type || null });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
