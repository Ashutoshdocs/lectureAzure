// A run-to-completion task. Container Apps Jobs start it, wait for exit, and stop billing.
// Works for manual, scheduled (cron) and event-driven (queue) triggers.
const steps = parseInt(process.env.STEPS || "5", 10);
const execution = process.env.CONTAINER_APP_JOB_EXECUTION_NAME || "local-run";
const replicaIdx = process.env.CONTAINER_APP_REPLICA_NAME || "local";

(async () => {
  console.log(`[${execution}] job started on ${replicaIdx}`);
  for (let i = 1; i <= steps; i++) {
    await new Promise((r) => setTimeout(r, 1000));
    console.log(`[${execution}] processed batch ${i}/${steps}`);
  }
  console.log(`[${execution}] done — exiting with code 0`);
  process.exit(0);
})();
