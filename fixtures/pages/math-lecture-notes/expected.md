---
id: u_f072aa98d52c9579da8129d38002e1a9
type: page
title: "Lecture 7: Eigenvalues & eigenvectors"
url: https://www.example.edu/~rkalnins/notes/linear-algebra/eigenvalues.html
canonical: https://www.example.edu/~rkalnins/notes/linear-algebra/eigenvalues.html
site: "example.edu"
author: "R. Kalniņš"
published: 2026-02-17T00:00:00.000Z
saved: 2026-10-22T12:00:00.000Z
updated: 2026-10-22T12:00:00.000Z
description: "Notes for MATH 2410, Lecture 7: characteristic polynomials, eigenspaces, and diagonalization."
tags: []
engine: defuddle@0.19.4 + turndown@7.2.4
---

# Lecture 7: Eigenvalues & eigenvectors

## 1. Definition

Let $A$ be an $n \times n$ matrix. A nonzero vector $\mathbf{v}$ is an eigenvector of $A$ if multiplying by the matrix only stretches it, so that $A\mathbf{v} = \lambda \mathbf{v}$ for some scalar $\lambda$, called the eigenvalue.

Rearranging, we need $(A - \lambda I)\mathbf{v} = \mathbf{0}$ to have a nonzero solution, which happens exactly when the matrix is singular:

$$
\det(A - \lambda I) = 0
$$

The left-hand side is a polynomial of degree $n$ in $\lambda$, the characteristic polynomial. Its roots are the eigenvalues, counted with multiplicity.

## 2. A worked example

Take the matrix below. Its characteristic polynomial factors neatly, which is not typical, but it keeps the arithmetic short.

$$
A = \begin{pmatrix} 4 & 1 \\ 2 & 3 \end{pmatrix}
$$

Expanding gives $\lambda^2 - 7\lambda + 10 = (\lambda - 5)(\lambda - 2)$, so the eigenvalues are 5 and 2. Substituting each back into $A - \lambda I$ and solving gives one eigenvector for each.

## 3. Diagonalization

When an $n \times n$ matrix has $n$ linearly independent eigenvectors, we can collect them as the columns of a matrix $P$ and write

$$
A = P D P^{-1}
$$

where $D$ is diagonal with the eigenvalues on its diagonal. Powers then become easy, since $A^k = P D^k P^{-1}$ and raising a diagonal matrix to a power only raises each diagonal entry.

**Exercise.** Show that a matrix with a repeated eigenvalue may or may not be diagonalizable, by finding one example of each.
