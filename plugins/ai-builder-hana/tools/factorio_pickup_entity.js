/** 捡起实体 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_pickup_entity";
export const description = "捡起指定位置的实体（拆除）。物品会返回角色背包。不能拆除其他角色。";
export const parameters = {
  type: "object",
  properties: {
    entity_name: { type: "string", description: "实体名称或 unit_number" },
    x: { type: "number" },
    y: { type: "number" },
  },
  required: ["entity_name", "x", "y"],
};
export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/agent/pickup", {
    entity_ref: isNaN(input.entity_name) ? input.entity_name : parseInt(input.entity_name),
    position: { x: input.x, y: input.y },
  });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
