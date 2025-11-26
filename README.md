# WordPress Manager for DirectAdmin + Apache

Hệ thống quản lý VPS sử dụng DirectAdmin + Apache để quản lý nhiều website WordPress với kiến trúc modular, dễ mở rộng.

## Tính năng

- ✅ Kiến trúc modular - dễ thêm/bớt chức năng
- ✅ Menu tương tác để quản lý các module
- ✅ Tự động phát hiện tất cả WordPress sites
- ✅ Hệ thống cache - lưu danh sách sites vào file, không cần quét lại mỗi lần
- ✅ Tự động rescan sau 24 giờ hoặc rescan thủ công
- ✅ Module chặn XML-RPC (xmlrpc.php)

## Yêu cầu

- DirectAdmin đã cài đặt
- Apache web server
- Bash shell
- Quyền root để chạy script

## Cài đặt

1. Clone hoặc tải các file vào thư mục:

```bash
cd /root
mkdir wp-manager
cd wp-manager
```

2. Copy các file vào thư mục:
   - `wp-manager.sh` - Script chính
   - `modules/xmlrpc-block.sh` - Module chặn XML-RPC
   - `modules/example-module.sh` - Template để tạo module mới
   - `install.sh` - Script cài đặt (tùy chọn)

3. Cấp quyền thực thi:

```bash
chmod +x wp-manager.sh
chmod +x modules/*.sh
chmod +x install.sh
```

Hoặc chạy script cài đặt tự động:

```bash
sudo ./install.sh
```

## Sử dụng

Chạy script với quyền root:

```bash
sudo ./wp-manager.sh
```

Hoặc:

```bash
sudo bash wp-manager.sh
```

## Menu chính

Script sẽ hiển thị menu với:
- Danh sách các module có sẵn
- Trạng thái của từng module (ENABLED/DISABLED)
- Số lượng WordPress sites được phát hiện
- Thông tin cache (thời gian cache)
- Option "r" để rescan WordPress sites

### Hệ thống Cache

Script tự động cache danh sách WordPress sites vào file `cache/wordpress_sites.txt`:
- **Lần đầu chạy**: Tự động quét và lưu vào cache
- **Các lần sau**: Đọc từ cache (nhanh hơn)
- **Cache hết hạn**: Tự động quét lại sau 24 giờ
- **Rescan thủ công**: Chọn option "r" trong menu để quét lại ngay

File cache được lưu tại:
- `cache/wordpress_sites.txt` - Danh sách sites (format: domain:docroot)
- `cache/wordpress_sites.timestamp` - Thời gian cache

## Module: XML-RPC Block

Module này cho phép chặn hoặc bỏ chặn truy cập file `xmlrpc.php` cho tất cả WordPress sites.

### Cách hoạt động

- **Enable**: Thêm rules vào file `.htaccess` của mỗi WordPress site để chặn truy cập xmlrpc.php
- **Disable**: Xóa các rules đã thêm
- **Status**: Hiển thị trạng thái chặn của từng site

### Rules được thêm vào .htaccess

```apache
# XML-RPC Block - WordPress Manager
# Added on YYYY-MM-DD HH:MM:SS
<Files xmlrpc.php>
    Order allow,deny
    Deny from all
</Files>
```

## Thêm module mới

Để thêm module mới, tạo file trong thư mục `modules/` với tên `module-name.sh` và implement các hàm sau:

```bash
# Mô tả module (hiển thị trong menu)
module-name_description() {
    echo "Description of module"
}

# Enable module
module-name_enable() {
    # Code để enable
    return 0
}

# Disable module
module-name_disable() {
    # Code để disable
    return 0
}

# Check status
module-name_status() {
    # Code để check status
}
```

Script chính sẽ tự động phát hiện và load module mới.

## Cấu trúc thư mục

```
wp-manager/
├── wp-manager.sh          # Script chính
├── install.sh             # Script cài đặt
├── modules/               # Thư mục chứa các module
│   ├── xmlrpc-block.sh    # Module chặn XML-RPC
│   └── example-module.sh  # Template để tạo module mới
├── config/                # Thư mục lưu trạng thái (tự động tạo)
│   └── *.status          # Files trạng thái của từng module
├── cache/                 # Thư mục lưu cache (tự động tạo)
│   ├── wordpress_sites.txt        # Danh sách WordPress sites
│   └── wordpress_sites.timestamp   # Thời gian cache
├── README.md             # Hướng dẫn chi tiết
└── QUICKSTART.md         # Hướng dẫn nhanh
```

## Lưu ý

- Script cần quyền root để truy cập DirectAdmin userdata
- Các thay đổi được thực hiện trực tiếp trên file `.htaccess` của từng site
- Nên backup trước khi enable các module
- Script tự động phát hiện WordPress sites bằng cách tìm file `wp-config.php`

## Troubleshooting

### Không tìm thấy WordPress sites

- Kiểm tra đường dẫn DirectAdmin: `/usr/local/directadmin/data/users`
- Đảm bảo các domain có file `wp-config.php` trong `public_html`

### Lỗi quyền truy cập

- Chạy script với quyền root: `sudo ./wp-manager.sh`
- Kiểm tra quyền của file `.htaccess`

### Module không hiển thị

- Đảm bảo file module có quyền thực thi: `chmod +x modules/module-name.sh`
- Kiểm tra tên hàm phải đúng format: `module-name_enable`, `module-name_disable`, etc.

## Phát triển

Để thêm chức năng mới, chỉ cần:
1. Tạo file module mới trong `modules/`
2. Implement các hàm required
3. Script sẽ tự động load và hiển thị trong menu

## License

Free to use and modify.

