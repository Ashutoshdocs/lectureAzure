# UI-Based Azure ARM Template Practical

## Objective

Learn how to work with Azure Resource Manager (ARM) templates entirely through the **Azure Portal UI**:

1. Open the custom deployment experience in the portal.
2. Load and review an ARM template in the editor.
3. Edit parameter values in the portal.
4. Validate and deploy the template.
5. Verify the resource in the portal.
6. Export a template from a deployed resource group.

This practical creates one Azure Storage Account using an ARM JSON template. No Azure CLI or PowerShell is required.

## Prerequisites

- An Azure subscription with permission to create resources.
- Permission to create a resource group and a storage account.
- A globally unique storage account name containing only lowercase letters and numbers, 3–24 characters long.

## Files

- `template.json` — ARM template for a StorageV2 account.
- `parameters.json` — example parameter values. Replace the storage account name with a globally unique name before deployment.

## Part 1 — Open the ARM template deployment UI

1. Sign in to the [Azure Portal](https://portal.azure.com).
2. Search for **Deploy a custom template**.
3. Open **Build your own template in the editor**.
4. Select **Load file** and upload `template.json` from this folder.
5. Select **Save**.

You can also navigate through **Create a resource** and search for **Template deployment (deploy using custom templates)**. Portal labels can change over time.

## Part 2 — Review the template

Understand the important ARM template sections:

- `$schema`: identifies the ARM deployment template schema.
- `contentVersion`: version of this template.
- `parameters`: values supplied when the template is deployed.
- `resources`: Azure resources that ARM will create.
- `type`: resource provider and resource type.
- `apiVersion`: version of the resource provider API used by the template.
- `dependsOn`: declares deployment dependencies when required.
- `properties`: configuration of the Azure resource.

The storage account name and location are parameters so that you can change them without editing the resource definition.

## Part 3 — Enter parameter values in the portal

1. After saving the template, select **Edit parameters**.
2. The portal displays the parameters declared in `template.json`.
3. Enter a globally unique value for `storageAccountName`.
4. Choose the required Azure region for `location`.
5. Select **Save**.

Example storage account name: `armuistorage12345` (use your own unique name).

The optional `parameters.json` file is included to teach the parameter-file structure. The portal's parameter editor may be used instead of uploading this file.

## Part 4 — Deploy from the UI

1. Select **Review + create**.
2. Wait for validation to complete.
3. Review the subscription, resource group, region, and parameter values.
4. Select **Create**.
5. Wait for the deployment notification to report success.
6. Open the resource group and confirm that the storage account exists.

Create a new resource group in the deployment flow if prompted. A suggested name is `rg-arm-ui-demo`.

## Part 5 — Verify the Storage Account in the portal

1. Open the created storage account.
2. On **Overview**, check the account name, resource group, location, and provisioning state.
3. Open **Configuration** and review the secure-transfer and minimum-TLS settings.
4. Open **Data storage → Containers** and create a container manually if you want to explore the data-plane UI. The ARM template creates the account and Blob service, not a container.

## Part 6 — Export an ARM template from the portal

This demonstrates the reverse workflow: create or select a resource, then inspect its generated template.

1. Open the resource group containing the storage account.
2. In the resource group menu, select **Export template** (the exact menu placement may vary).
3. Review the generated ARM template.
4. Select **Download** if you want to save the exported template.
5. Explain to learners that exported templates are a starting point and may need cleanup, parameterization, and testing before reuse.

You can also open an individual resource and look for **Automation → Export template**, where supported.

## Important teaching notes

- ARM templates describe the desired resource configuration; the Azure Resource Manager deployment engine performs the deployment.
- The portal is the user interface used to author, parameterize, validate, and submit the template.
- A successful deployment does not mean every application-level setting has been configured.
- Storage account names are globally unique across Azure.
- Do not put passwords, access keys, or other secrets directly in template files or parameter files.
- The exported template may contain generated values or settings that are not suitable for direct reuse.

## Cleanup

To avoid ongoing charges:

1. Open **Resource groups** in the Azure Portal.
2. Open `rg-arm-ui-demo` (or the resource group name you selected).
3. Confirm that it contains only resources created for this practical.
4. Select **Delete resource group**.
5. Type the resource group name to confirm, then select **Delete**.

Deleting the resource group permanently deletes the resources inside it. Do not delete a resource group that contains resources you need.

## Expected result

A StorageV2 storage account is deployed successfully by loading an ARM JSON template and completing the deployment entirely through the Azure Portal UI.
