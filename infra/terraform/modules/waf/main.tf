# =====================================================================
# WAF (REGIONAL, ALB 부착) — 다층 방어
# 설계 근거: analysis/2026-design.md §5
# 원칙:
#  - 제공 API 비정상 요청 → 403(block), 미제공 경로 → 404(앱/ALB가 처리, WAF 미차단)
#  - 정상 트래픽 UA(Python aiohttp / curl)는 절대 차단하지 않음
#  - 이미지 업로드(PUT) 바이너리 body 오탐 방지 (Common 그룹 body 룰 override)
# =====================================================================

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.prefix}-waf-web-acl"
  description = "WAF for ALB - layered defense"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # --- 관리형 1: Common (body 검사 룰은 이미지 업로드 오탐 방지 위해 Count 전환) ---
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
        rule_action_override {
          name = "CrossSiteScripting_BODY"
          action_to_use {
            count {}
          }
        }
        rule_action_override {
          name = "GenericRFI_BODY"
          action_to_use {
            count {}
          }
        }
        rule_action_override {
          name = "GenericLFI_BODY"
          action_to_use {
            count {}
          }
        }
        rule_action_override {
          name = "EC2MetaDataSSRF_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # --- 관리형 2: KnownBadInputs ---
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # --- 관리형 3: SQLi ---
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLi"
      sampled_requests_enabled   = true
    }
  }

  # --- 관리형 4: IP 평판 ---
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 4
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IpReputation"
      sampled_requests_enabled   = true
    }
  }

  # --- 커스텀 10: 메서드 화이트리스트 (GET/POST/PUT/HEAD/OPTIONS 외 차단) ---
  rule {
    name     = "MethodWhitelist"
    priority = 10
    action {
      block {}
    }
    statement {
      not_statement {
        statement {
          or_statement {
            dynamic "statement" {
              for_each = ["get", "post", "put", "head", "options"]
              content {
                byte_match_statement {
                  search_string         = statement.value
                  positional_constraint = "EXACTLY"
                  field_to_match {
                    method {}
                  }
                  text_transformation {
                    priority = 0
                    type     = "LOWERCASE"
                  }
                }
              }
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "MethodWhitelist"
      sampled_requests_enabled   = true
    }
  }

  # NOTE: 스캐너/취약경로(wp-admin, .env 등) 차단 룰은 의도적으로 배제.
  # task.md §7: "제공하는 API 외의 요청은 404" — 이런 경로는 전부 미제공 경로라
  # 403으로 막으면 그 자체로 룰 위반(2025 PathWhitelist와 동일 실수). ALB 기본 404로 흘려보낸다.

  # --- 커스텀 40: 이메일 형식 검증 (/v1/user POST, 유효 이메일 없으면 403) ---
  rule {
    name     = "UserEmailValidation"
    priority = 40
    action {
      block {}
    }
    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = "/v1/user"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          byte_match_statement {
            search_string         = "post"
            positional_constraint = "EXACTLY"
            field_to_match {
              method {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          not_statement {
            statement {
              regex_pattern_set_reference_statement {
                arn = aws_wafv2_regex_pattern_set.email_pattern.arn
                field_to_match {
                  body {
                    oversize_handling = "CONTINUE"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "COMPRESS_WHITE_SPACE"
                }
              }
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "UserEmailValidation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "UserGetEmailValidation"
    priority = 41
    action {
      block {}
    }
    statement {
      and_statement {
        statement {
          byte_match_statement {
            search_string         = "/v1/user"
            positional_constraint = "EXACTLY"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          byte_match_statement {
            search_string         = "get"
            positional_constraint = "EXACTLY"
            field_to_match {
              method {}
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
        statement {
          not_statement {
            statement {
              regex_pattern_set_reference_statement {
                arn = aws_wafv2_regex_pattern_set.email_query_pattern.arn
                field_to_match {
                  query_string {}
                }
                text_transformation {
                  priority = 0
                  type     = "URL_DECODE"
                }
                text_transformation {
                  priority = 1
                  type     = "LOWERCASE"
                }
              }
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "UserGetEmailValidation"
      sampled_requests_enabled   = true
    }
  }

  # --- 커스텀 50: 악성 User-Agent 차단 (정상 aiohttp/curl 제외) ---
  rule {
    name     = "BlockedUserAgents"
    priority = 50
    action {
      block {}
    }
    statement {
      regex_pattern_set_reference_statement {
        arn = aws_wafv2_regex_pattern_set.blocked_user_agents.arn
        field_to_match {
          single_header {
            name = "user-agent"
          }
        }
        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockedUserAgents"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.prefix}-waf"
    sampled_requests_enabled   = true
  }
}

# NOTE: 레이트리밋 룰은 의도적으로 배제. 정상 부하가 소수 IP(채점 aiohttp)에서
# 대량 유입되므로 per-IP 레이트리밋은 정상 트래픽 오탐(availability 붕괴) 위험이 큼.
# 악성은 볼류메트릭이 아닌 '헤더 이상값' 형태이므로 시그니처 방어로 대응한다.

# =====================================================================
# 정규식 패턴 세트 (세트당 최대 10패턴 → 주제별 분리로 커버리지 확장)
# =====================================================================
resource "aws_wafv2_regex_pattern_set" "email_pattern" {
  name  = "${var.prefix}-email-pattern"
  scope = "REGIONAL"

  # body에 유효한 이메일이 존재하는지 검사 (없으면 위 not_statement로 차단→403)
  regular_expression {
    regex_string = "\"email\"\\s*:\\s*\"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}\""
  }
}

resource "aws_wafv2_regex_pattern_set" "email_query_pattern" {
  name  = "${var.prefix}-email-query-pattern"
  scope = "REGIONAL"

  regular_expression {
    regex_string = "(^|&)email=[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}(&|$)"
  }
}

resource "aws_wafv2_regex_pattern_set" "blocked_user_agents" {
  name  = "${var.prefix}-blocked-user-agents"
  scope = "REGIONAL"

  # ⚠️ 정상 UA(python/aiohttp, curl, wget, mozilla/chrome, kube-probe,
  #    ELB-HealthChecker, Amazon CloudFront)는 절대 포함 금지.
  #    특히 kube-probe는 차단되면 파드가 재시작되어 availability가 붕괴한다.
  regular_expression { regex_string = "sqlmap|nikto|nmap|masscan|zgrab|zmap|nuclei|wpscan" }
  regular_expression { regex_string = "gobuster|feroxbuster|ffuf|dirbuster|wfuzz|dirsearch|katana|hakrawler|gospider|amass" }
  regular_expression { regex_string = "hydra|havij|acunetix|nessus|metasploit|burpsuite|openvas|qualys|netsparker|appscan|nexpose" }
  regular_expression { regex_string = "slowloris|hulk|goldeneye|loic|hoic|ddos|loadgen|stress" }
  regular_expression { regex_string = "bot|attack|malicious|exploit|payload|inject|intrud|breach" }
  regular_expression { regex_string = "backdoor|rootkit|trojan|malware|ransom|scanner|fuzzer|intruder|recon|brute" }
  regular_expression { regex_string = "hack|hax|pwn|crack|redteam|pentest|cyberattack" }
  regular_expression { regex_string = "webshell|reverseshell|bindshell|shellcode|mimikatz|cobaltstrike|empire|sliver|havoc|bloodhound" }
  regular_expression { regex_string = "rce|lfi|rfi|sqli|xss|ssrf|xxe|cmdi|cve|zeroday|0day" }
  regular_expression { regex_string = "phish|spoof|steal|exfil|keylog|credential|bypass|evasion|botnet|mirai|emotet|qbot" }
}

# =====================================================================
# ALB 연결 + 전량 로깅 (Athena 분석 원천)
# =====================================================================
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-${var.prefix}"
  retention_in_days = 7
}

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
  # 전량 로깅(정상/차단 모두) → 당일 악성 패턴 실시간 역산에 사용
}
