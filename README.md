Ops-Core: The Enterprise Lifecycle Toolkit
Architect: Gavin Dobbs | Status: Production-Ready
Focus: Infrastructure-as-Code (IaC), Database Integrity, Cost Optimization

1. The Philosophy: "Precision Creates Speed"
In 20+ years of managing high-availability infrastructure (Financial/Banking & Intel Validation), I have learned that "fast" is often a synonym for "fragile." This repository contains the codified standard operating procedures (SOPs) I utilize to ensure Predictability, Auditability, and Stability across the infrastructure lifecycle.

This toolkit addresses the three critical phases of Systems Administration:

Provisioning: Zero-touch, standardized deployment.

Hygiene: Automated identification of waste (Orphaned Resources).

Decommissioning: Safety-gated destruction of critical assets.

2. The Modules
A. The "Zero-Touch" Hyper-V Provisioner
File: Deploy-HyperV-Core.ps1

The Problem: Manual VM builds introduce configuration drift. Humans forget separate partitions for Logs, they misconfigure subnets, or they forget to trigger the initial patch cycle.

The Solution: A PowerShell-driven engine that separates the Physical Build (VHDX layout, ISO mounting) from the Logical Configuration (IP injection, Domain Join).

Key Features:

PowerShell Direct Injection: Uses the VM Bus to inject Static IPs and Domain Credentials before the network stack is fully active. Solves the "Chicken and Egg" remote management issue.

Best-Practice Disk Layout: Automatically provisions a dedicated 40GB D:\Logs volume to ensure OS stability during log spikes.

SCCM/MECM Integration: Triggers the specific WMI GUIDs (000...0021 & 000...0113) to force an immediate "Machine Policy" and "Update Deployment" cycle, ensuring the server is patched before it enters production.

B. The Orphaned Resource Auditor
File: Audit-OrphanedVMs.ps1 (Logic Overview)

The Problem: In virtualized environments, "Zombie Servers" (powered on, but unused) bleed budget.

The Solution: An algorithmic auditor that scans vCenter/Hyper-V for "Ghost" signals.

Logic:

Traffic Analysis: Checks for Network Throughput < 10KB/sec over 30 days.

Login Stagnation: Queries LastLogonTimeStamp against the Domain Controller for the computer object.

Dependency Check: Scans the CMDB/DNS for active pointers.

Result: Generates a "Kill List" report for management review, preventing accidental deletion of quiet-but-critical servers (like licensing relays).

C. The Defensive Database Drop Protocol (@@WHATIF)
File: usp_Admin_SafeDropDB.sql

The Problem: DROP DATABASE is immediate and unforgiving. In high-pressure environments, fatigue leads to mistakes.

The Solution: A Stored Procedure that acts as a "Dead Man's Switch" for database destruction.

Key Features:

Audit Accountability: Requires a @TicketRef parameter (e.g., Jira/ServiceNow Ticket #). If you can't prove why you are deleting it, the script refuses to run.

The Transactional Safety Valve: Wraps the destruction command in a BEGIN TRAN.

Default Dry-Run: The @DryRun bit defaults to 1. The script calculates the impact, prints the would-be destruction log, and ROLLBACKS the transaction automatically unless explicitly overridden.

Dynamic SQL Injection Safety: Uses sp_executesql and sysname types to prevent string-based vulnerabilities.

3. Usage & Implementation
Hyper-V: Designed for Server 2019/2022 Core or Desktop Experience. Requires Admin credentials for the Host and Domain Join permissions.

SQL: Safe to deploy on SQL 2016+ Standard/Enterprise. Recommended installation in the master or Admin_Tools database.

4. About the Author
Gavin Dobbs is a Senior Systems Administrator & Jr. DBA based in Clarkston, WA. With a background in SOX-regulated financial environments ($29B Assets) and hardware validation workflows, Gavin specializes in bridging the gap between "Executive Requirements" and "Technical Execution."
