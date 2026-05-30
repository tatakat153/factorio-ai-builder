/** 批量建造 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_build_batch";
export const description = `使用预定义模板批量建造。模板会自动处理传送带、电线杆、爪子的布局。
遇到障碍或材料不足时会暂停并报告。

可用模板: smelter_row(电炉排), stone_furnace_row(石炉排), assembler_grid(组装机网格), miner_array(采矿机阵列), steam_power_unit(蒸汽发电), belt_bus(传送带总线), lab_cluster(实验室集群), wall_segment(墙壁段)

参数：
- template_name: 模板名
- anchor_x, anchor_y: 建造起始坐标
- count: 重复数量（沿 repeat_x 方向）
- recipe_name: 配方名（需要配方的模板使用）`;

export const parameters = {
  type: "object",
  properties: {
    template_name: { type: "string" },
    anchor_x: { type: "number" },
    anchor_y: { type: "number" },
    count: { type: "number", default: 1 },
    recipe_name: { type: "string" },
  },
  required: ["template_name", "anchor_x", "anchor_y", "count"],
};
export async function execute(input, ctx) {
  const data = await post(ctx, "/api/v1/agent/build/batch", {
    template_name: input.template_name,
    anchor: { x: input.anchor_x, y: input.anchor_y },
    count: input.count,
    recipe_name: input.recipe_name || null,
  });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
