provider "aws" {
region = "ap-south-1"
profile = "avanishgupta"
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  
  public_key = "${tls_private_key.example.public_key_openssh}"
}
resource "local_file" "mykey" {
content = "${tls_private_key.example.private_key_pem}"
filename="C:/Users/91893/Downloads/mykey2301.pem"
file_permission=0400
}


resource "aws_security_group" "allow_tlsp" {
  name        = "allow_tlsp"
  description = "Allow TLS inbound traffic"

 ingress {
    from_port = 0
    to_port = 0
    protocol = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
   egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow_tlsp"
  }
}




resource "aws_instance" "LinuxOS" {
  ami   ="ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name="${aws_key_pair.generated_key.key_name}"
  vpc_security_group_ids = ["${aws_security_group.allow_tlsp.id}"]
connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.example.private_key_pem
    host     = aws_instance.LinuxOS.public_ip
  }
 provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
  tags = {
    Name = "Myfirstos"
  }
}





resource "aws_ebs_volume" "persistent_storage" {
  availability_zone = aws_instance.LinuxOS.availability_zone
  size              = 1
  tags = {
    Name = "ebs_volume"
  }
}

resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.persistent_storage.id
  instance_id = aws_instance.LinuxOS.id
 
}







resource "null_resource" "nullremote3"  {
depends_on = [
    aws_volume_attachment.ebs_att,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.example.private_key_pem
    host     = aws_instance.LinuxOS.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Avanish474/AWS-infrastructure-using-Terraform-without-manual-approach-.git /var/www/html/"
    ]
  }
}

resource "aws_s3_bucket" "b" {
 
  acl    = "private"
   //force_detach=true
  tags = {
    Name        = "My bucket"

  }
}
resource "aws_s3_bucket_public_access_block" "publicobject" {
  bucket = "${aws_s3_bucket.b.id}"

  block_public_acls   = false
  block_public_policy = false
}
resource "aws_s3_bucket_object" "object" {
  bucket = "${aws_s3_bucket.b.id}"
  key    = "justice_league.jpg"
  source = "C:/Users/91893/Pictures/justice.jpg"
  acl    = "public-read"
  content_type = "image/jpg"
}





resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Some comment"
}
data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.b.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.b.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "example" {
  bucket = "${aws_s3_bucket.b.id}"
  policy = "${data.aws_iam_policy_document.s3_policy.json}"
}
locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.b.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
  default_root_object = "index.html"

  logging_config {
    include_cookies = false
    bucket          = "avanish2301.s3.amazonaws.com"
    prefix          = "myprefix"
  }

  

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}



resource "null_resource" "nulllocal1"  {
depends_on = [
    aws_cloudfront_distribution.s3_distribution,
  ]
        provisioner "local-exec" {
	    command = "echo  ${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key}>public_ip &&cd C:/Program Files (x86)/Google/Chrome/Application && chrome  ${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.object.key}"
  	}
}

