{
    junk(x)::
    local y = {a:x};
    local bed = import "junk2.jsonnet";
    {
        some: {
            one: y,
            two: x
        },
        input: y,
        bed: bed,
    },
}

