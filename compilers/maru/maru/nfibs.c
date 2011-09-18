#include <stdio.h>

int fibs(int n)
{
  return (n < 2) ? 1 : (fibs(n - 1) + fibs(n - 2) + 1);
}

int main()
{
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
  printf("%d\n", fibs(35));
}
