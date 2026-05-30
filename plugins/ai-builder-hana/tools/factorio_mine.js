/** 挖掘 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_mine";
export const description = "挖掘指定类型的资源（铁矿、铜矿、石头、树木等）。角色会自动走到最近的资源点。可指定 max_count 限制挖掘量。挖掘完毕后物品自动进入角色背包。";
export const parameters = {
  type: "object",
  properties: {
    resource_name: { type: "string", description: "资源名: iron-ore, copper-ore, stone, coal, tree-01 等" },
    max_count: { type: "number", description: "最大挖掘数量，默认 50", default: 50 },
    near_x: { type: "number", description: "优先搜索此坐标附近的资源" },
    near_y: { type: "number" },
  },
  required: ["resource_name"],
};
export async function execute(input, ctx) {
  const body = { resource_name: input.resource_name, max_count: input.max_count || 50 };
  if (input.near_x !== undefined) body.position_hint = { x: input.near_x, y: input.near_y || 0 };
  const data = await post(ctx, "/api/v1/agent/mine", body);
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
