from locust import HttpUser, task, between

class NMTKUser(HttpUser):
    wait_time = between(1, 5)

    # NeuroCNL tasks
    @task(3)
    def neurocnl_parse(self):
        self.client.post("/api/parse", json={
            "spec": "The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5"
        }, name="NeuroCNL Parse")

    @task(1)
    def neurocnl_generate(self):
        self.client.post("/api/generate", json={
            "spec": "The sensory neuron MUST fire",
            "backend": "nengo"
        }, name="NeuroCNL Generate")

    # Neurosim tasks
    @task(2)
    def neurosim_preview(self):
        graph = {
            "nodes": [{"id": "n1", "component_id": "lif", "parameters": {}, "position": [0, 0]}],
            "edges": [],
            "metadata": {}
        }
        self.client.post("/api/neurosim/preview", json={
            "graph": graph,
            "duration_ms": 100
        }, name="Neurosim Preview")

    # Neurohub tasks
    @task(4)
    def neurohub_list_projects(self):
        self.client.get("/api/neurohub/projects", name="Neurohub List Projects")

    @task(2)
    def neurohub_list_assets(self):
        self.client.get("/api/neurohub/assets", name="Neurohub List Assets")

    # Neurosense tasks
    @task(2)
    def neurosense_list_sessions(self):
        self.client.get("/api/neurosense/sessions", name="Neurosense List Sessions")

    # Neurochip tasks
    @task(1)
    def neurochip_list_targets(self):
        self.client.get("/api/neurochip/targets", name="Neurochip List Targets")

    # Neurobench tasks
    @task(1)
    def neurobench_list_benchmarks(self):
        self.client.get("/api/neurobench/benchmarks", name="Neurobench List Benchmarks")

    def on_start(self):
        """Called when a User starts before any task is scheduled"""
        pass
