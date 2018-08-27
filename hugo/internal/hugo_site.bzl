
def copy_to_dir(ctx, srcs, dirname):
    outs = []
    for i in srcs:
        o = ctx.actions.declare_file(dirname + "/" + i.basename)
        ctx.actions.run_shell(
            inputs = [i],
            outputs = [o],
            command = "cp '%s' '%s'" % (i.path, o.path),
        )
        outs.append(o)
    return outs


def _hugo_site_impl(ctx):
    tar_file = ctx.outputs.tar_file
    hugo = ctx.executable.hugo
    hugo_inputs = [hugo]
    hugo_outputs = [tar_file]
    hugo_args = []
    
    # Copy the config file into place
    config_file = ctx.actions.declare_file(ctx.file.config.basename)
    ctx.actions.run_shell(
        inputs = [ctx.file.config],
        outputs = [config_file],
        command = "cp '%s' '%s'" % (ctx.file.config.path, config_file.path),
    )
    hugo_inputs.append(config_file)
    
    # Copy all the files over
    content_files = copy_to_dir(ctx, ctx.files.content, "content")
    static_files = copy_to_dir(ctx, ctx.files.static, "static")
    image_files = copy_to_dir(ctx, ctx.files.images, "images")
    layout_files = copy_to_dir(ctx, ctx.files.layouts, "layouts")
    data_files = copy_to_dir(ctx, ctx.files.data, "data")
    hugo_inputs += content_files + static_files + image_files + layout_files + data_files

    # Copy the theme
    if ctx.attr.theme:
        theme = ctx.attr.theme.hugo_theme
        hugo_args += ["--theme", theme.name]
        
        for i in theme.files :
            input_path = ""
            if i.short_path.startswith(theme.path):
                input_path = i.short_path[len(theme.path):]
                o_filename = "/".join(["themes", theme.name, input_path])
            elif i.short_path.startswith("../"):
                o_filename = "/".join(["themes", theme.name] + i.short_path.split("/")[2:])
            else:
                o_filename = "/".join(["themes", theme.name, i.short_path])
            
            o = ctx.actions.declare_file(o_filename)
            ctx.actions.run_shell(
                inputs = [i],
                outputs = [o],
                command = "cp '%s' '%s'" % (i.path, o.path),
            )
            hugo_inputs.append(o)

    # Prepare hugo command
    hugo_args += [
        "--config", config_file.path,
        "--contentDir", "/".join([config_file.dirname, "content"]),
        "--themesDir", "/".join([config_file.dirname, "themes"]),
        "--destination", "/".join([config_file.dirname, ctx.label.name]),
    ]

    if ctx.attr.quiet:
        hugo_args.append("--quiet")
    if ctx.attr.verbose:
        hugo_args.append("--verbose")
    if ctx.attr.base_url:
        hugo_args.append("--baseURL", ctx.attr.base_url)
    hugo_command = " ".join([hugo.path] + hugo_args)


    # Declare the site directory for output
    site_dir = ctx.actions.declare_directory(tar_file.dirname + "/" + ctx.label.name, sibling=None)
    hugo_outputs.append(site_dir)

    # Prepare zip command
    zip_args = ["tar", "-C", tar_file.dirname + "/" + ctx.label.name , "-cf", ctx.outputs.tar_file.path]
    zip_args.append(".")
    zip_command = " ".join(zip_args)


    # Generate site and zip up the publishDir
    ctx.actions.run_shell(
        mnemonic = "GoHugo",
        progress_message = "Generating hugo site",
        command = " && ".join([hugo_command, zip_command]),
        inputs = hugo_inputs,
        outputs = hugo_outputs,
    )

    # Return files and 'hugo_site' provider
    return struct(
        files = depset(hugo_outputs),
        webroot = site_dir,
        hugo_site = struct(
            name = ctx.label.name,
            content = content_files,
            static = static_files,
            data = data_files,
            config = config_file,
            theme = ctx.attr.theme,
            archive = tar_file,
        ),
    )


hugo_site = rule(
    implementation = _hugo_site_impl,
    attrs = {
        # Hugo config file
        "config": attr.label(
            allow_files = FileType([".toml", ".yaml", ".json"]),
            single_file = True,
            mandatory = True,
        ),
        # Files to be included in the content/ subdir
        "content": attr.label_list(
            allow_files = True,
            mandatory = True,
        ),
        # Files to be included in the static/ subdir
        "static": attr.label_list(
            allow_files = True,
        ),
        # Files to be included in the images/ subdir
        "images": attr.label_list(
            allow_files = True,
        ),
        # Files to be included in the layouts/ subdir
        "layouts": attr.label_list(
            allow_files = True,
        ),
        # Files to be included in the data/ subdir
        "data": attr.label_list(
            allow_files = True,
        ),
        # The hugo executable
        "hugo": attr.label(
            default = "@hugo//:hugo",
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
        # Optionally set the base_url as a hugo argument
        "base_url": attr.string(),
        "theme": attr.label(
            providers = ["hugo_theme"],
        ),
        # Emit quietly
        "quiet": attr.bool(
            default = True,
        ),
        # Emit verbose
        "verbose": attr.bool(
            default = False,
        ),
    },
    outputs = {
        "tar_file": "%{name}_site.tar",
    }
)

def _hugo_site_serve_impl(ctx) :

    site_script="""#!/bin/bash
    if [[ -n "$TEST_SRCDIR" && -d "$TEST_SRCDIR" ]]; then
        # use $TEST_SRCDIR if set.
        export RUNFILES="$TEST_SRCDIR"
    elif [[ -z "$RUNFILES" ]]; then
        # canonicalize the entrypoint.
        pushd "$(dirname "$0")" > /dev/null
        abs_entrypoint="$(pwd -P)/$(basename "$0")"
        popd > /dev/null
        if [[ -e "${abs_entrypoint}.runfiles" ]]; then
            # runfiles dir found alongside entrypoint.
            export RUNFILES="${abs_entrypoint}.runfiles"
        elif [[ "$abs_entrypoint" == *".runfiles/"* ]]; then
            # runfiles dir found in entrypoint path.
            export RUNFILES="${abs_entrypoint%.runfiles/*}.runfiles"
        else
            # runfiles dir not found: fall back on current directory.
            export RUNFILES="$PWD"
        fi
    fi

    set -x

    export PORT="%{port}"
    export TAR_FILE="$PWD/%{tar_file}"
    export STATICWEBSERVER="$PWD/%{staticwebserver}"

    echo "Serving files out of $TAR_FILE on port $PORT"
    
    mkdir site
    tar -C site -xf $TAR_FILE
    find .
    ${STATICWEBSERVER} --port "$PORT" --webroot "$PWD/site"
    """

    tar_short_path = ctx.attr.hugo_site.files.to_list()[0].short_path

    script = site_script  \
        .replace("%{port}",ctx.attr.port)  \
        .replace("%{tar_file}",tar_short_path)  \
        .replace("%{staticwebserver}",ctx.executable._webserver.short_path )

    ctx.actions.write(ctx.outputs.executable, script , True)
    return struct(runfiles = ctx.runfiles(files = [ctx.executable._webserver] + ctx.attr.hugo_site.files.to_list() ))

hugo_site_serve = rule(
    implementation = _hugo_site_serve_impl,
    attrs = {
        "hugo_site" : attr.label(
            allow_files = True,
            mandatory = True,
        ),
        "port" : attr.string(
            default= "1313"
        ),
        "_webserver" : attr.label(
            default = "//hugo/staticwebserver:cmd",
            allow_files = True,
            executable = True,
            cfg = "host",
        )
    },
    executable = True
)
