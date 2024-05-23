- Currently reads an add function from `add.o` and executes it from zig.

To compile add.c:

> [!WARNING]
> Do not use gcc, theres an endbr64 instruction on the top that causes issues

```bash
clang -c add.c -o add.o

# Alternatively you can use the zig c compiler

zig cc -c add.c -o add.o
```

To execute the add function via zig:

```bash
zig build run
```

![alt text](image.png)

## References

- [Cloudflare blogs](https://blog.cloudflare.com/how-to-execute-an-object-file-part-1/)