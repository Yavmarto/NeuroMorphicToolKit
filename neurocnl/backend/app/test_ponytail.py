import numpy as np

data = np.array([0.0, 0.0, 0.0, 1.2, 0.0, 3.4])
flat = np.ravel(data)
non_zeros = flat[flat != 0]
preview = non_zeros.tolist()[:16] if non_zeros.size > 0 else flat.tolist()[:16]
print("preview:", preview)

data2 = np.array([0.0, 0.0])
flat2 = np.ravel(data2)
non_zeros2 = flat2[flat2 != 0]
preview2 = non_zeros2.tolist()[:16] if non_zeros2.size > 0 else flat2.tolist()[:16]
print("preview2:", preview2)

data3 = np.array(5.0)
flat3 = np.ravel(data3)
non_zeros3 = flat3[flat3 != 0]
preview3 = non_zeros3.tolist()[:16] if non_zeros3.size > 0 else flat3.tolist()[:16]
print("preview3:", preview3)
