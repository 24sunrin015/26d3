# 버킷 이름 전역 유일성 확보 (비번호 + 랜덤 접미)
resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "images" {
  bucket = "${var.prefix}-images-${var.student_id}-${random_id.suffix.hex}"

  force_destroy = true # 대회 후 clean destroy
}

# 퍼블릭 접근 전면 차단 — 다운로드는 CloudFront(OAC)로만
resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
