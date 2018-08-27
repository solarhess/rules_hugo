
def _hugo_theme_impl(ctx):
    build_file = ctx.build_file_path
    relative_path = build_file[:build_file.rfind('/')]
    return struct(
        hugo_theme = struct(
            name = ctx.attr.theme_name or ctx.label.name,
            files = depset(ctx.files.srcs),
            path = relative_path
        ),
    )

hugo_theme = rule(
    implementation = _hugo_theme_impl,
    attrs = {
        "theme_name": attr.string(
        ),
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        )
    },
)
    
