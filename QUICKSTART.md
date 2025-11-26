# Hướng dẫn nhanh

## Cài đặt

```bash
# 1. Copy files vào thư mục (ví dụ: /root/wp-manager)
cd /root
mkdir wp-manager
cd wp-manager
# Copy tất cả files vào đây

# 2. Cấp quyền thực thi
chmod +x wp-manager.sh
chmod +x modules/*.sh
chmod +x install.sh

# 3. Chạy script cài đặt (tùy chọn)
./install.sh
```

## Sử dụng

```bash
# Chạy với quyền root
sudo ./wp-manager.sh
```

## Menu chính

Script sẽ hiển thị:
- Số lượng WordPress sites được phát hiện
- Danh sách các module có sẵn
- Trạng thái của từng module (ENABLED/DISABLED)

Chọn số tương ứng với module để:
- **Enable**: Bật chức năng
- **Disable**: Tắt chức năng  
- **Status**: Xem trạng thái chi tiết

## Module: XML-RPC Block

**Mục đích**: Chặn truy cập file `xmlrpc.php` để bảo mật WordPress sites

**Cách hoạt động**:
- Thêm rules vào `.htaccess` của mỗi WordPress site
- Rules sẽ chặn tất cả truy cập đến `xmlrpc.php`

**Sử dụng**:
1. Chọn module "Block XML-RPC Access" từ menu
2. Chọn "1" để Enable
3. Script sẽ tự động áp dụng cho tất cả WordPress sites

## Thêm module mới

1. Copy file `modules/example-module.sh` thành tên module mới
2. Đổi tên file và các hàm theo format: `module-name_function()`
3. Implement 3 hàm bắt buộc:
   - `module-name_description()` - Mô tả hiển thị trong menu
   - `module-name_enable()` - Code để bật chức năng
   - `module-name_disable()` - Code để tắt chức năng
   - `module-name_status()` - Code để kiểm tra trạng thái

4. Script sẽ tự động phát hiện và load module mới

## Lưu ý quan trọng

- ⚠️ Luôn backup trước khi enable các module
- ⚠️ Script cần quyền root để hoạt động
- ⚠️ Các thay đổi được thực hiện trực tiếp trên files của sites
- ✅ Script tự động phát hiện WordPress sites
- ✅ Có thể enable/disable bất cứ lúc nào

## Troubleshooting

**Không tìm thấy WordPress sites?**
- Kiểm tra đường dẫn DirectAdmin: `/usr/local/directadmin/data/users`
- Đảm bảo các domain có file `wp-config.php`

**Lỗi quyền truy cập?**
- Chạy với quyền root: `sudo ./wp-manager.sh`
- Kiểm tra quyền của thư mục DirectAdmin

**Module không hiển thị?**
- Kiểm tra file có quyền thực thi: `chmod +x modules/module-name.sh`
- Kiểm tra tên hàm phải đúng format

