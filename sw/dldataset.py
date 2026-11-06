import kagglehub

# Download latest version
path = kagglehub.dataset_download("manideep1108/tusimple", output_dir="data/tusimple")

print("Path to dataset files:", path)