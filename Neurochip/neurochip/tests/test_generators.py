import io
import zipfile

from neurochip.app.schemas.estimation import NetworkInput
from neurochip.app.services.loihi_generator import generate_loihi_package
from neurochip.app.services.teensy_generator import generate_teensy_project


def get_mock_network():
    return NetworkInput(
        num_neurons=100,
        num_synapses=1000,
        neuron_model="LIF",
        populations=[{"name": "pop1", "size": 100}],
        connections=[{"pre": "pop1", "post": "pop1", "weight_count": 1000}],
        weight_bit_width=32,
        network_depth=10,
    )


def test_generate_teensy_project():
    net = get_mock_network()
    zip_bytes = generate_teensy_project(net, bit_width=8)

    assert isinstance(zip_bytes, bytes)

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        file_list = zf.namelist()
        assert "neurochip_firmware/src/main.ino" in file_list
        assert "neurochip_firmware/src/network_params.h" in file_list
        assert "neurochip_firmware/src/lif_engine.h" in file_list
        assert "neurochip_firmware/platformio.ini" in file_list
        assert "neurochip_firmware/README.md" in file_list

        readme = zf.read("neurochip_firmware/README.md").decode()
        assert "Neurons: 100" in readme
        assert "Weight bit-width: 8-bit" in readme


def test_generate_loihi_package():
    net = get_mock_network()
    zip_bytes = generate_loihi_package(net, bit_width=8)

    assert isinstance(zip_bytes, bytes)

    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        file_list = zf.namelist()
        assert "loihi_deploy/deploy.py" in file_list
        assert "loihi_deploy/config.json" in file_list
        assert "loihi_deploy/crossbar_weights.bin" in file_list
        assert "loihi_deploy/README.md" in file_list

        readme = zf.read("loihi_deploy/README.md").decode()
        assert "Neurons: 100" in readme
        assert "Weight bit-width: 8-bit" in readme
