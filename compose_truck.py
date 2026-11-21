from PIL import Image

logo_path = 'app/assets/brand/dropoff_logo.png'
truck_path = 'assets/brand/map_truck_3d.png'
out_truck = 'app/assets/brand/map_truck_3d.png'

logo = Image.open(logo_path).convert('RGBA')
data = logo.getdata()
new_data = []
for item in data:
    if item[0] > 240 and item[1] > 240 and item[2] > 240:
        new_data.append((255, 255, 255, 0))
    else:
        new_data.append(item)
logo.putdata(new_data)

logo_size = 180
logo = logo.resize((logo_size, logo_size), Image.LANCZOS)

truck = Image.open(truck_path).convert('RGBA')
truck_w, truck_h = truck.size
# Truck cab is at top center (truck points UP/north)
truck_x = (truck_w - logo_size) // 2
truck_y = int(truck_h * 0.08)
truck.paste(logo, (truck_x, truck_y), logo)
truck.save(out_truck)
print('Truck saved:', out_truck, truck.size)
EOF