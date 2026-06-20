# Hybrid Administration Platform (HAP)

# Engineering Guide

Welcome to the Hybrid Administration Platform.

This document serves as the engineering entry point for all development work.

Before implementing new functionality, every engineer should understand the architectural principles that guide the platform.

This guide explains where information lives, the expected development workflow, and the order in which project documentation should be consumed.

---

# Engineering Philosophy

HAP is developed as a long-lived enterprise software platform.

The objective is not simply to build administrative tools, but to establish reusable infrastructure capable of supporting multiple organizations, providers, workflows, and cloud environments.

Every implementation should improve the platform as a whole.

The preferred solution is the one that best supports long-term maintainability, extensibility, consistency, and reuse.

---

# Read This Documentation First

Documentation is intentionally organized so each document answers one question.

Read them in the following order.

## 1. PROJECT_CHARTER.md

**Question answered**

> Why does HAP exist?

Defines the mission, vision, and non-negotiable architectural principles of the platform.

---

## 2. DESIGN_PRINCIPLES.md

**Question answered**

> How are engineering decisions made?

Defines the architectural philosophy that guides platform evolution.

---

## 3. ARCHITECTURE.md

**Question answered**

> How is HAP built?

Describes the platform architecture, layering, dependencies, and major subsystems.

---

## 4. CODING_STANDARDS.md

**Question answered**

> How should code be written?

Defines engineering expectations for all production code.

---

## 5. ROADMAP.md

**Question answered**

> Where is HAP going?

Describes the strategic direction of future platform development.

---

## 6. PROJECT_STATUS.md

**Question answered**

> What is currently being developed?

Provides the current development snapshot.

---

## 7. VERSION.md

**Question answered**

> What version of HAP is this?

Defines the current development version and release information.

---

## 8. CHANGELOG.md

**Question answered**

> What has already been completed?

Records released functionality.

---

## 9. Architecture Decision Records (ADR)

**Question answered**

> Why was the platform designed this way?

Documents the reasoning behind major architectural decisions.

Every significant architectural decision should result in a new ADR.

---

## 10. EXTENSIBILITY_SDK.md

**Question answered**

> How do I extend the platform?

Defines the contracts for providers, workflows, plugins, and future platform extensions.

---

# Development Workflow

Every feature should follow the same engineering process.

## Step 1

Understand the architectural problem.

Do not begin implementation until the problem has been fully understood.

---

## Step 2

Review existing platform infrastructure.

If reusable infrastructure already exists, consume it.

If multiple future features will require the same capability, expand the infrastructure before implementing the feature.

---

## Step 3

Design first.

Architecture precedes implementation.

Major architectural changes should be discussed before code is written.

---

## Step 4

Implement.

Implement production-quality functionality.

Avoid temporary solutions.

Avoid customer-specific implementations.

---

## Step 5

Test.

Every feature requires automated testing.

Existing tests must continue to pass.

---

## Step 6

Document.

Documentation is part of the implementation.

A feature is not complete until the relevant documentation has been updated.

---

# Engineering Expectations

When contributing to HAP:

* Preserve provider abstraction.
* Preserve domain model integrity.
* Reuse shared infrastructure.
* Avoid duplication.
* Prefer composition over specialization.
* Design for future providers.
* Design for future organizations.
* Design for multiple tenants.
* Design for multiple cloud environments.

When uncertain, choose the solution that best improves the platform rather than the current milestone.

---

# Architectural Rules

The following rules should rarely require exceptions.

* Business logic never depends on specific providers.
* Providers never expose native provider objects.
* Authentication is a platform service.
* Organizations and tenants are separate concepts.
* Providers execute against Provider Contexts.
* Platform behavior should be configuration-driven.
* Dependencies flow downward through the architecture.
* Shared infrastructure is preferred over duplicated implementation.
* Workflows orchestrate capabilities rather than implementing provider logic.
* UI consumes application services rather than infrastructure.

---

# Definition of Done

A feature is complete only when:

* Architecture remains consistent.
* Shared infrastructure has been expanded where appropriate.
* Automated tests pass.
* Documentation has been updated.
* Public interfaces remain stable.
* Existing functionality continues to work.
* The implementation satisfies the Project Charter and Design Principles.

---

# Working With ChatGPT

The Hybrid Administration Platform has been developed collaboratively with ChatGPT as a software engineering partner.

Future development sessions should begin by reviewing:

1. ENGINEERING_GUIDE.md
2. PROJECT_CHARTER.md
3. DESIGN_PRINCIPLES.md
4. ARCHITECTURE.md
5. ROADMAP.md
6. PROJECT_STATUS.md

Development should continue from the current roadmap while preserving all established architectural principles.

Treat every implementation as production-quality software engineering rather than code generation.

Design reusable infrastructure before implementing milestone-specific functionality.

When architectural trade-offs exist, prefer the solution that best supports the long-term evolution of the platform.

---

# Final Principle

The Hybrid Administration Platform is not built milestone by milestone.

It is built capability by capability.

Each milestone should leave the platform stronger, more reusable, and easier to extend than it was before.

Future providers, workflows, organizations, and cloud environments should benefit from today's engineering decisions without requiring architectural redesign.
