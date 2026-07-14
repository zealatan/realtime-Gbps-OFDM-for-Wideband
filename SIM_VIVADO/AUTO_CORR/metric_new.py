import pandas as pd
import matplotlib.pyplot as plt

df = pd.read_csv("metric_dump.csv")

cols = [c for c in df.columns if c != "time"]
n = len(cols)

plt.figure(figsize=(10, 3*n))

for i, col in enumerate(cols):
    plt.subplot(n, 1, i+1)
    plt.plot(df[col])
    plt.title(col)
    plt.grid()

plt.tight_layout()
plt.show()
