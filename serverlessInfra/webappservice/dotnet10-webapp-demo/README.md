# .NET 10 Web App Demo — Azure App Service

A small ASP.NET Core **.NET 10** web app for the **.NET runtime stack** on **Azure App Service (Linux)**. It serves a landing page and two JSON endpoints, and uses no NuGet packages.

## Project structure

```
dotnet10-webapp-demo/
├── Dotnet10WebappDemo.csproj   # net10.0, Microsoft.NET.Sdk.Web
├── Program.cs                  # minimal API: static files + /api routes
├── wwwroot/
│   └── index.html              # landing page (live runtime info, health badge)
├── deploy.ps1                  # one-step deploy for Windows PowerShell
├── deploy.sh                   # same, for bash / Git Bash / Cloud Shell
├── .gitignore
└── README.md
```

## Endpoints

| Route         | Description                                             |
|---------------|---------------------------------------------------------|
| `/`           | Landing page (`wwwroot/index.html`)                     |
| `/api/health` | `{ "status": "healthy", "time": "..." }`                |
| `/api/info`   | .NET version, site name, region, uptime, memory         |

## Prerequisites

- [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0). Check with `dotnet --version`, which should print `10.x`.
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- An Azure subscription

```powershell
az login
az account show -o table            # confirm the right subscription
```

Confirm that .NET 10 is offered in your region:

```powershell
az webapp list-runtimes --os-type linux -o table | findstr /i dotnet
```

You should see `DOTNETCORE:10.0`.

## Run locally

```powershell
dotnet run --urls http://localhost:5000
# open http://localhost:5000
```

---

## Deploy: Option 1, the script (recommended on Windows)

From the `dotnet10-webapp-demo` folder in PowerShell:

```powershell
# allow the script to run in this window only
Set-ExecutionPolicy -Scope Process Bypass

# brand-new app (creates resource group, plan, web app)
.\deploy.ps1

# ...or deploy into an EXISTING web app
.\deploy.ps1 -App blazecheck -ResourceGroup test
```

The script builds the app, zips it correctly, creates the Azure resources if needed, sets the runtime to `DOTNETCORE|10.0` and the startup command, deploys the zip and prints the URL.

## Deploy: Option 2, one command (`az webapp up`)

No zip and no local build: Azure builds the project from source. Run it from the project folder:

```powershell
az webapp up `
  --name my-dotnet10-demo-app `
  --resource-group rg-dotnet10-demo `
  --location centralindia `
  --runtime "DOTNETCORE:10.0" `
  --sku B1 `
  --os-type Linux
```

> In PowerShell, the line-continuation character is the backtick `` ` ``, not `\`.
> The app name must be globally unique, because it becomes `https://<name>.azurewebsites.net`.

## Deploy: Option 3, manual steps in PowerShell

```powershell
# Variables: PowerShell syntax is $NAME = "value" (bash-style NAME=value does NOT work)
$RG       = "rg-dotnet10-demo"
$LOCATION = "centralindia"
$PLAN     = "plan-dotnet10-demo"
$APP      = "my-dotnet10-demo-app"

# 1. Resource group + Linux plan + web app on .NET 10
az group create --name $RG --location $LOCATION
az appservice plan create --name $PLAN --resource-group $RG --sku B1 --is-linux
az webapp create --name $APP --resource-group $RG --plan $PLAN --runtime "DOTNETCORE:10.0"

# 2. Startup command
az webapp config set --name $APP --resource-group $RG --startup-file "dotnet Dotnet10WebappDemo.dll"

# 3. Build
dotnet publish -c Release -o .\publish

# 4. Zip the CONTENTS of publish (the DLL must be at the root of the zip)
cd .\publish
Compress-Archive -Path * -DestinationPath ..\app.zip -Force
cd ..

# 5. Deploy
az webapp deploy --name $APP --resource-group $RG --src-path app.zip --type zip

# 6. Open
az webapp browse --name $APP --resource-group $RG
```

---

## Moving an existing app (e.g. `blazecheck`) to .NET 10

```powershell
az webapp config set --name blazecheck --resource-group test `
  --linux-fx-version "DOTNETCORE|10.0" `
  --startup-file "dotnet Dotnet10WebappDemo.dll"
```

Then deploy with `.\deploy.ps1 -App blazecheck -ResourceGroup test`.

## Troubleshooting

```powershell
# check runtime + startup command
az webapp config show --name <APP> --resource-group <RG> --query "{runtime:linuxFxVersion, startup:appCommandLine}" -o table

# live logs
az webapp log config --name <APP> --resource-group <RG> --docker-container-logging filesystem
az webapp log tail   --name <APP> --resource-group <RG>
```

| Symptom / log message | Fix |
|---|---|
| `argument --resource-group/-g: expected one argument` | The variable is empty. In PowerShell, set it with `$RG = "name"`, or type the name directly. |
| `'zip' is not recognized` | PowerShell has no `zip` command. Use `Compress-Archive` or `.\deploy.ps1`. |
| Deploy stuck on "Starting the site..." | Wrong runtime or startup command. Run the `config set` command above and check that the runtime is `DOTNETCORE\|10.0`. |
| "You must install or update .NET" | The app's runtime isn't 10.0. Set `--linux-fx-version "DOTNETCORE\|10.0"`. |
| "Could not find ... Dotnet10WebappDemo.dll" | The zip has a `publish\` folder inside it. Zip from **inside** `publish`. |
| `DOTNETCORE:10.0` not in `list-runtimes` | Your region doesn't offer .NET 10 yet. Try another `--location`, or use the .NET 8 demo. |

## Clean up

```powershell
az group delete --name rg-dotnet10-demo --yes --no-wait
```
