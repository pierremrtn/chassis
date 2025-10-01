---
icon: car-side
---

# About Chassis

> **Rigid in Structure, Flexible in Implementation.**

## Overview

Chassis is an opinionated architectural framework for Flutter that provides a solid foundation for professional, scalable, and maintainable applications. It guides your project's structure by combining the clarity of **MVVM** with a pragmatic, front-end friendly implementation of **CQRS** principles.

Think of it like the chassis of a car: it provides a rigid, reliable frame so you can focus on building the features that make your application unique. 🏎️

## The Philosophy: Structure by Design

Good architecture shouldn't rely on developer discipline alone. Chassis is designed around a few core principles to make best practices the path of least resistance.

* 🏛️ **Structure by Design:** Chassis enforces a clear separation of concerns through its defined data flow. This makes it intuitive to write clean, organized code that is easy for anyone on the team to navigate.
* ⚡ **Reactive by Default:** Built around streaming data with `WatchQuery` to create UIs that are "live" and automatically update when your underlying data changes.
* 🧩 **Rigid Structure, Flexible Logic:** The overall flow of data is consistent and predictable. However, your actual business logic within each component remains isolated, flexible, and easy to change.
* ✅ **Testability First:** Every layer, from ViewModels to business logic Handlers, is decoupled by design, making it simple to mock dependencies and test any part of your application in isolation.
* 🧑‍💻 **Developer Experience Focused:** We aim for minimal boilerplate and a clean, intuitive API. The goal is to make building on a solid architecture feel productive, not restrictive.

## Packages

Chassis is composed of two packages that work together: a core architectural library and a Flutter presentation layer.

### **`chassis`**: The Core Architectural Layer

A pure Dart package providing the foundational pieces for your application's business logic, completely independent of the UI.

### **`chassis_flutter`**: The Presentation Layer

This package seamlessly connects your core logic to the Flutter widget tree.

***

## Chassis vs. State Management

The Flutter ecosystem has excellent state management libraries like **BLoC** and **Riverpod**. **Chassis is not a replacement for them—it operates at a different level of abstraction.**

BLoC and Riverpod are primarily **tools for state management**. Chassis is an **opinionated framework for application architecture** that uses those tools as part of its foundation.

| Aspect                  | BLoC / Riverpod                                                              | Chassis                                                                        |
| ----------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **Primary Goal** | Efficiently manage state and rebuild the UI when it changes.                 | Enforce a consistent, scalable, and decoupled application structure.           |
| **Where Logic Lives** | **Flexible.** Logic can live in a `Bloc`, service, or repository.            | **Prescriptive.** Business logic **must** live in dedicated `Handler` classes. |
| **Architectural Style** | **High Freedom.** Provides powerful primitives to design your own structure. | **Low Freedom.** Provides a strict structure in exchange for consistency.      |

### When to Choose Chassis

Chassis is designed for scenarios where architectural consistency and scalability are the highest priorities:

* You are building a **large, complex application**.
* **Consistency across a large team** is critical.
* A **strict separation of concerns** is a project requirement.

**The Trade-off:** There is more upfront boilerplate for simple features. This "ceremony" is the price for long-term scalability and maintainability.