# Practical 2 – Why use Azure Deployment Stacks instead of a simple Bicep deployment?

## Learning objectives

Understand what Deployment Stacks add on top of Bicep/ARM deployments, and where they are useful.

## Core comparison

| Capability | Ordinary Bicep / ARM resource-group deployment | Deployment Stack |
|---|---|---|
| Declare Azure resources | Yes | Yes, using the same Bicep/ARM templates |
| Preview changes | `az deployment group what-if` | `az stack-whatif group create` |
| Track resources in a stack object | No dedicated stack resource | Yes |
| Know which resources are managed by this stack | Not as a first-class stack relationship | Yes |
| Handle resources removed from the template | Incremental mode generally leaves them | Configure `action-on-unmanage` to detach or delete |
| Deny settings on managed resources | Not a deployment feature of ordinary Bicep deployment | Yes, stack deny settings can restrict operations |
| Resource lifecycle governance | Mostly deployment workflow plus RBAC/Policy | Stack-level management and lifecycle controls |
| Bicep language | Same | Same |

## Why is this better?

Deployment Stacks do not make Bicep syntax better or replace Bicep. They add a management layer around a template deployment.

### 1. Resource ownership / management tracking

A stack records the resources it manages. This helps a platform team identify which resources belong to a particular infrastructure deployment.

### 2. Explicit handling of removed declarations

With a normal Incremental Bicep deployment, removing a resource block from the template does not automatically delete the existing resource.

With a stack, choose the action when a resource becomes unmanaged:
- `detachAll`: leave the Azure resource in place, but stop managing it through that stack.
- `deleteResources`: delete resources that are removed from the stack's template.

This makes the lifecycle decision explicit. Always preview the change before using `deleteResources`.

### 3. Deny settings

A stack can apply deny settings to managed resources. These settings can help prevent accidental modifications or deletions by principals that would otherwise have permissions, depending on the selected mode and exclusions.

Common modes include:
- `none`: no stack deny assignment.
- `denyDelete`: deny deletion of managed resources.
- `denyWriteAndDelete`: deny write and delete operations on managed resources, subject to documented exclusions and authorization behaviour.

Deny settings are not a replacement for least-privilege RBAC, Azure Policy, resource locks, or backup. Test the effect carefully and understand how exclusions and privileged operations work.

### 4. Repeatable platform deployments

Stacks are useful when a platform team deploys a standard set of resources for each application or environment and wants a durable record of the managed set and an explicit unmanage policy.

## Hands-on comparison

### A. Ordinary Bicep

1. Deploy a template with a Storage Account and two containers using `az deployment group create`.
2. Remove one container declaration from the template.
3. Deploy again.
4. Observe: the omitted container normally remains under Incremental deployment.

### B. Deployment Stack

1. Deploy the same resource set using `az stack group create`.
2. Remove one container declaration.
3. Run `az stack-whatif group create`.
4. Deploy with `--action-on-unmanage detachAll`: resource remains in Azure but is detached from stack management.
5. Reset the lab, then repeat with `--action-on-unmanage deleteResources` in a disposable resource group: removed resource is deleted as part of stack update.

See Practical 3 for the full commands and separate template files.

## When should you use ordinary Bicep?

- Small/simple deployments where resource lifecycle tracking is not needed.
- A pipeline already handles drift checks, cleanup, and governance.
- You want to deploy a template without adding stack management and deny-assignment considerations.
- You are learning Bicep syntax and basic ARM deployments.

## When should you consider Deployment Stacks?

- Central platform teams need to manage a defined set of resources as a unit.
- You need an explicit policy for resources removed from the template.
- You need stack-level deny settings to reduce accidental changes/deletions.
- You need a durable record of the resources associated with a deployment stack.
- You operate repeatable landing-zone or application-environment deployments.

## Instructor takeaway

**Bicep describes what to deploy. A Deployment Stack adds management of the deployed resource collection and controls for what happens when resources leave that collection.**
