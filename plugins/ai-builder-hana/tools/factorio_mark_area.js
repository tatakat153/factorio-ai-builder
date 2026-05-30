/**
 * 圈地标记 (Planner)
 */
import { post } from "../lib/bridge.js";

export const name = "factorio_mark_area";
export const description = `在指定矩形区域创建标记，用于后续详细查询。标记后可用 factorio_get_area_detail 获取该区域的详细压缩数据。
AI 应主动删除不再需要的标记以节省内存。

参数：
- mark_id: 唯一标记 ID（如 "iron_field_1"）
- x1, y1: 区域左上角
- x2, y2: 区域右下角
- label: 标记描述（如 "铁矿区"）`;

export const parameters = {
  type: "object",
  properties: {
    mark_id: { type: "string", description: "唯一标记 ID" },
    x1: { type: "number", description: "区域左上角 X" },
    y1: { type: "number", description: "区域左上角 Y" },
    x2: { type: "number", description: "区域右下角 X" },
    y2: { type: "number", description: "区域右下角 Y" },
    label: { type: "string", description: "标记描述" },
  },
  required: ["mark_id", "x1", "y1", "x2", "y2"],
};

export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/world/mark", {
    mark_id: input.mark_id,
    corner1: { x: input.x1, y: input.y1 },
    corner2: { x: input.x2, y: input.y2 },
    label: input.label || "",
  });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
