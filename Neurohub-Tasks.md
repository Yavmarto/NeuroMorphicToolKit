# Neurohub — Concrete Tasks to 100% POC Readiness

1. **Fix Backend Database Imports**
   - *Description:* `from db.database import engine` fails because `db` is not in the PYTHONPATH or structured as a sibling package correctly. Restructure imports or adjust `sys.path` in `app/main.py`.
   - *Impact:* Prevents backend crashes on startup.

2. **Build Suite Dashboard Frontend**
   - *Description:* The frontend is 238 LOC of scaffolds. Implement the `DashboardScreen` to poll all other module `/health` endpoints and display a green/red status grid.
   - *Impact:* Essential for the "unified hub" vision of the POC.

3. **Implement Activity Feed Widget**
   - *Description:* Wire the `ActivityFeed` UI component to the `/api/neurohub/activity` backend route.
   - *Impact:* Completes the dashboard experience.
