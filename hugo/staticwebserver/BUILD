#exports_files(["staticwebserver"], visibility=["//visibility:public"])

load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_binary(
    name = "cmd",
    importpath = "github.com/solarhess/rules_hugo/hugo/staticwebserver",
    srcs = ["staticwebserver.go"],
    visibility = ["//visibility:public"],
)
