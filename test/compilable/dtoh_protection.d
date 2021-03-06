/**
https://issues.dlang.org/show_bug.cgi?id=21218

REQUIRED_ARGS: -HC -o-
TEST_OUTPUT:
---
// Automatically generated by Digital Mars D Compiler

#pragma once

#include <stddef.h>
#include <stdint.h>


struct S1
{
    int32_t a;
protected:
    int32_t b;
    int32_t c;
    int32_t d;
private:
    int32_t e;
public:
    S1()
    {
    }
};

class S2
{
public:
    int32_t af();
protected:
    int32_t bf();
    int32_t cf();
    int32_t df();
public:
    S2()
    {
    }
};

class C1
{
public:
    int32_t a;
protected:
    int32_t b;
    int32_t c;
    int32_t d;
private:
    int32_t e;
};

struct C2
{
    virtual int32_t af();
protected:
    virtual int32_t bf();
    int32_t cf();
    int32_t df();
};

struct Outer
{
private:
    int32_t privateOuter;
public:
    struct PublicInnerStruct
    {
    private:
        int32_t privateInner;
    public:
        int32_t publicInner;
        PublicInnerStruct() :
            publicInner()
        {
        }
    };

private:
    struct PrivateInnerClass
    {
    private:
        int32_t privateInner;
    public:
        int32_t publicInner;
        PrivateInnerClass() :
            publicInner()
        {
        }
    };

public:
    class PublicInnerInterface
    {
    public:
        virtual void foo() = 0;
    };

private:
    enum class PrivateInnerEnum
    {
        A = 0,
        B = 1,
    };

public:
    typedef PrivateInnerEnum PublicAlias;
    Outer()
    {
    }
};
---
*/

module compilable.dtoh_protection;

extern(C++) struct S1
{
    public int a;
    protected int b;
    package int c;
    package(compilable) int d;
    private int e;
}

extern(C++, class) struct S2
{
    public int af();
    protected int bf();
    package int cf();
    package(compilable) int df();
    private int ef();
}

extern(C++) class C1
{
    public int a;
    protected int b;
    package int c;
    package(compilable) int d;
    private int e;
}

extern(C++, struct) class C2
{
    public int af();
    protected int bf();
    package int cf();
    package(compilable) int df();
    private int ef();
}

extern(C++) struct Outer
{
    private int privateOuter;

    static struct PublicInnerStruct
    {
        private int privateInner;
        int publicInner;
    }

    private static struct PrivateInnerClass
    {
        private int privateInner;
        int publicInner;
    }

    static interface PublicInnerInterface
    {
        void foo();
    }

    private static enum PrivateInnerEnum
    {
        A,
        B
    }

    public alias PublicAlias = PrivateInnerEnum;
}
