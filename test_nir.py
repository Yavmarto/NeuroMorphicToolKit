import nir
import numpy as np

def main():
    import os
    path = "paper/02_cnn/cnn_sinabs.nir"
    if not os.path.exists(path):
        print("Not found:", path)
        return
    g = nir.read(path)
    for name, node in g.nodes.items():
        if isinstance(node, nir.IF):
            r = np.asarray(node.r)
            print(f"Node {name}: IF, R max = {np.max(r)}, min = {np.min(r)}")

if __name__ == "__main__":
    main()
