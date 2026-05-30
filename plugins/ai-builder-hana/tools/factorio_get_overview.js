/**
 * 获取区域概览 (Planner)
 * 稀疏摘要：chunk 级别的资源和建筑统计
 */
import { get } from "../lib/bridge.js";

export const name = "factorio_get_overview";
export const description = `获取指定区域的大致资源与建筑摘要。返回 chunk 级别的稀疏概览，不包含每个实体的详细信息。
使用场景：AI 需要了解"周围有什么"时调用。每个 chunk 返回资源类型+估算量和建筑类型+数量。

参数：
- center_x, center_y: 概览中心坐标
- radius_chunks: 半径（chunk 数，默认 3）。每个 chunk 是 32x32 tiles`;

export const parameters = {
  type: "object",
  properties: {
    center_x: { type: "number", description: "中心 X 坐标" },
    center_y: { type: "number", description: "中心 Y 坐标" },
    radius_chunks: { type: "number", description: "查询半径（chunk 数），默认 3", default: 3 },
  },
  required: ["center_x", "center_y"],
};

export async function execute(input, ctx) {
  const data = await get(ctx,
    `/api/v1/world/overview?center_x=${input.center_x}&center_y=${input.center_y}&radius_chunks=${input.radius_chunks || 3}`
  );
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
