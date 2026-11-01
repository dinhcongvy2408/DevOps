# VPC của taskhub: 2 subnet public (có route ra Internet qua IGW) + 2 subnet private
# (chỉ có route local). KHÔNG có NAT Gateway — xem ADR-0005.
#
# Subnet dùng for_each trên map có khóa "a"/"b" (hậu tố AZ), không dùng count trên list:
# địa chỉ là aws_subnet.public["a"], không phải aws_subnet.public[0] → bớt một AZ ở đầu
# danh sách không làm các subnet còn lại bị đánh số lại và bị thay thế (bài 02, bài 04).

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  }
}

# Subnet "public" là public VÌ route table này có 0.0.0.0/0 → IGW, không phải vì cái tên.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

# Không khai báo route nào: chỉ còn route "local" mà AWS tự thêm cho mọi route table.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-private-rt"
  }
}

# Lặp qua resource aws_subnet.public (không phải biến): cùng khóa "a"/"b", và mỗi phần tử có sẵn .id
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
