/** 放置单个实体 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_place_entity";
export const description = `在指定坐标放置一个实体（建筑、传送带、电线杆等）。自动校验物品是否足够、位置是否可建造。
方向(direction): 0=北, 1=东北, 2=东, 3=东南, 4=南, 5=西南, 6=西, 7=西北`;

export const parameters = {
  type: "object",
  properties: {
    entity_name: { type: "string" },
    x: { type: "number" },
    y: { type: "number" },
    direction: { type: "number", default: 0 },
  },
  required: ["entity_name", "x", "y"],
};
export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/agent/build/single", {
    entity_name: input.entity_name,
    position: { x: input.x, y: input.y },
    direction: input.direction || 0,
  });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
