# HILOP Patch Notes - Graph Force Delegated Prompt

Date: 2026-07-04

## Purpose

Corrects the launch regression where Microsoft Graph delegated sign-in was not prompting during runtime launch.

## Changes

- Forces Microsoft Graph delegated authentication to use `-ForceRefresh` during launch-time provider initialization.
- Prevents an existing/stale/app-only cached session from silently satisfying the Graph provider and skipping the delegated browser prompt.
- Removes a duplicate Graph authentication session request in the Microsoft Graph provider.
- Keeps the previous launch UI polish and menu/list contrast fixes intact.

## Expected behavior

For a live runtime profile with Microsoft Graph enabled and delegated authentication enabled or implied by the Graph provider's Interactive authentication setting, launching the console should open the browser delegated sign-in prompt before the workflow selector/dashboard is shown.
