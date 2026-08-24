output "project_name" {
  value = aws_codebuild_project.image_build.name
}

output "source_key" {
  value = var.source_key
}
