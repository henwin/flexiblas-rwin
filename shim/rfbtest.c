/* .C-callable access to the FlexiBLAS API of the libflexiblas.dll that R has
 * already loaded through its forwarding Rblas.dll. Looking the functions up
 * in that module (instead of linking libflexiblas_api) makes sure the test
 * talks to the same instance that R's BLAS calls go through. */
#include <windows.h>
#include <stddef.h>

static FARPROC fb(const char *name)
{
    HMODULE h = GetModuleHandleA("libflexiblas.dll");
    return h ? GetProcAddress(h, name) : NULL;
}

void rfb_loaded(int *ok)
{
    *ok = GetModuleHandleA("libflexiblas.dll") != NULL;
}

void rfb_current(char **name)
{
    int (*f)(char *, size_t) = (int (*)(char *, size_t)) fb("flexiblas_current_backend");
    if (f) f(name[0], 64);
}

void rfb_load_library(char **path, int *id)
{
    int (*f)(const char *) = (int (*)(const char *)) fb("flexiblas_load_backend_library");
    *id = f ? f(path[0]) : -2;
}

void rfb_load(char **name, int *id)
{
    int (*f)(const char *) = (int (*)(const char *)) fb("flexiblas_load_backend");
    *id = f ? f(name[0]) : -2;
}

void rfb_switch(int *id, int *ret)
{
    int (*f)(int) = (int (*)(int)) fb("flexiblas_switch");
    *ret = f ? f(*id) : -2;
}

void rfb_set_threads(int *n)
{
    void (*f)(int) = (void (*)(int)) fb("flexiblas_set_num_threads");
    if (f) f(*n);
}

void rfb_get_threads(int *n)
{
    int (*f)(void) = (int (*)(void)) fb("flexiblas_get_num_threads");
    *n = f ? f() : -2;
}
