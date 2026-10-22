---
id: u_dc6beb067256ae05becdeab539951988
type: page
title: "What a year of on-call taught our team"
url: https://medium.example/@saskia.montrose/what-a-year-of-on-call-taught-our-team-4f9a2c1b7e3d?source=rss----5517fd7b58a6---4
canonical: https://medium.example/@saskia.montrose/what-a-year-of-on-call-taught-our-team-4f9a2c1b7e3d
site: "Medium"
author: "Saskia Montrose"
published: 2026-10-14T16:20:11.904Z
saved: 2026-10-22T12:00:00.000Z
updated: 2026-10-22T12:00:00.000Z
description: "Fewer pages, shorter incidents, and the three habits that made the rotation bearable."
image: https://miro.medium.example/v2/resize:fit:1200/1*Qx7pZ3kT2bLmN8vR4sWc0A.jpeg
tags: []
engine: defuddle@0.19.4 + turndown@7.2.4
---

# What a year of on-call taught our team

## Fewer pages, shorter incidents, and the three habits that made the rotation bearable

![A wall of monitoring dashboards in a dark room](https://miro.medium.example/v2/resize:fit:1400/format:webp/1*Qx7pZ3kT2bLmN8vR4sWc0A.jpeg)

*Photo by Ruben Alcott, used with permission*

Last October our team of six took over on-call for the payments platform. We had inherited a rotation where the median engineer was paged eleven times a week, and nearly half of those pages resolved themselves before anyone opened a laptop.

A year later the median is under two pages a week, and our incidents are shorter. None of what we did was clever. It was mostly a matter of being stubborn about three habits.

## 1. Every page gets a ticket

If an alert woke someone up, it got a ticket the next morning, even if the fix was obvious. The ticket had one question: should this alert exist? In the first three months we deleted or downgraded forty-one alerts this way.

An alert that nobody acts on is not a safety net.

It is a tax on sleep.

## 2. Handoffs are written down

At the end of each shift the outgoing engineer writes five lines: what fired, what they did, what is still open, what they suspect, and what they would do next. It takes ten minutes and saves the next person an hour of archaeology.

## 3. The rotation is protected time

Whoever is on call does not pick up feature work. They fix the things that paged them, improve runbooks, and go home on time. Our product manager hated this for about six weeks and then noticed that feature work had stopped being interrupted.
