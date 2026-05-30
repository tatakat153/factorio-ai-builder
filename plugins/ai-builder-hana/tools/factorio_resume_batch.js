/** 恢复批量 (Executor) */
import { post } from "../lib/bridge.js";
export const name = "factorio_resume_batch";
export const description = `恢复暂停的批量建造。resolution 选项:
- skip_obstacles: 跳过有障碍的位置
- destroy_obstacles: 摧毁障碍物后继续
- force_continue: 忽略障碍强行继续
- cancel: 取消批量`;

export const parameters = {
  type: "object",
  properties: { batch_id: { type: "string" }, resolution: { type: "string", default: "skip_obstacles" } },
  required: ["batch_id"],
};
export async function execute(input, ctx) {
  const data = await post(ctx, `/api/v1/agent/build/batch/${input.batch_id}/resume`, {
    resolution: input.resolution || "skip_obstacles",
  });
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}
