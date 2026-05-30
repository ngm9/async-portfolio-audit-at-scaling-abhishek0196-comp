# Task Overview

This financial trading application handles millions of trades, portfolio aggregations, and regulatory audit logs. While the FastAPI APIs are operational, the app struggles with severe database bottlenecks—portfolio queries are slow, audit retrievals time out, and nightly risk calculations overwhelm the system. All endpoints and business logic are in place; the main challenge is to optimize the Postgres schema and async DB logic for high throughput, real-time compliance, and minimal event-loop blocking.

# Database Access
- Host: <DROPLET_IP>
- Port: 5432
- Database: tradingdb
- Username: traderadmin
- Password: tradepass2024

### Objectives
- Improve the most essential relationships and constraints across the main tables to ensure reliable links and cleaner query paths.
- Adjust a few key database access points—both in request handlers and background routines—to follow async-safe patterns, reducing unnecessary blocking.
- Identify the slowest or most frequently used queries and refine them with small structural or indexing improvements.
- Enhance the audit logging flow so it consistently records events and avoids gaps during typical usage.
- Validate that these targeted changes help the service behave more reliably under normal read/write activity.

### How to Verify
- Use database tools to get a quick sense of whether your indexing or schema refinements result in more efficient access patterns.
- Hit a handful of reporting and audit-related endpoints to confirm noticeably smoother responses after your changes.
- Trigger common trading or portfolio updates and confirm audit entries appear consistently, even with a bit of simultaneous system activity.
- Run a few concurrent requests to observe whether interactions feel more predictable and avoid avoidable stalls.

### Helpful Tips
- The core tables hold millions of rows and are interconnected, but their current structure and indexing patterns create friction for both reporting and logging workloads.
- Some API endpoints appear to block the event loop because they use synchronous database access or heavy bulk-processing logic. Background audit/event writes may also be running in ways that are not fully safe for async environments or transactions.
- As you review the system, pay particular attention to how table design, index strategy, and foreign key relationships impact both OLTP operations and analytical queries.
- Consider how concurrency, transaction isolation, and long-running batch processes affect consistency, especially when reporting and audit trails are involved.
- If you notice clear defects—either in schema design, async handling, or logic flows—treat them as opportunities to stabilize and improve the overall system.
