# Azure App Service Autoscale Demo

Each instance of the web app shows its **own page** — a different name (Aurora, Ember, Nebula…) and color, derived from the instance ID. When autoscale adds instances, refreshing the browser shows different pages.

## Prerequisites
- Azure CLI logged in: `az login` (and `az account set -s <subscription>` if you have several)
- `zip` and `curl`
- Cost: one **S1** plan (~$0.10/hr per instance, up to 3 instances during the demo). Run `5-cleanup.sh` afterwards.

## Run it

| Step | Command | What happens |
|---|---|---|
| 1 | `./1-deploy.sh` | Creates RG, S1 Linux plan, Node 20 web app, turns **ARR affinity off**, zip-deploys the code |
| 2 | `./2-autoscale.sh` | Autoscale on the plan: min 1 / max 3. **Out +1** when avg CPU > 60% for 5 min, **in -1** when < 30% for 10 min, 5 min cooldown |
| 3 | `./3-trigger-load.sh` | Safe CPU load for 12 min (pass minutes as arg). Ctrl+C stops it instantly |
| 4 | `./4-watch.sh` (2nd terminal) | Instance count, CPU, which pages are being served, autoscale events |
| 5 | `./5-cleanup.sh` | Deletes everything |

Edit `config.sh` to change region, thresholds or max instances.

## What you'll see
1. **Before:** browser shows one name, e.g. `Aurora`. The live table says *1 instance seen*.
2. **~5–10 min into the load:** autoscale fires. `4-watch.sh` shows plan count `2`, and a second name appears.
3. **In the browser:** click *Auto-reload* (or keep refreshing). The page alternates between e.g. **Aurora** (blue) and **Ember** (orange); the live table flashes when a new instance first answers.
4. Load keeps going → a 3rd instance after the 5-min cooldown.
5. **After stopping load:** CPU drops, and ~10–15 min later it scales back in.

You can also confirm in the portal: **App Service plan → Scale out (App Service plan) → Run history**.

## Why the load is safe
- No traffic flood: just 3 tiny requests every 20 s from your machine.
- `/burn?seconds=N` spins the CPU of **only the instance that receives it**, capped at **120 s** per request, with a watchdog that stops it automatically.
- The load script ends on its own after the duration, and Ctrl+C sends `/stop`.
- `max-count 3` caps how far (and how expensively) it can scale.

## App endpoints
- `/` – the instance page + live instance table
- `/api/whoami` – JSON identity of the instance that answered
- `/burn?seconds=60` – time-boxed CPU load on that instance
- `/stop` – stop load on the instance that answers (call several times to reach all)
- `/healthz` – health check

## Gotchas
- **Same page every refresh?** ARR affinity is still on. Run `az webapp update -g rg-autoscale-demo -n <app> --client-affinity-enabled false`, or use a private window.
- **Short on time?** Prove the multi-page part instantly with a manual scale: `az appservice plan update -g rg-autoscale-demo -n plan-autoscale-demo --number-of-workers 3` (autoscale may later override it).
- Autoscale only works on **Standard (S1) and above**; Basic and Free can't autoscale.
- New instances take 1–2 min to warm up before they answer requests.
