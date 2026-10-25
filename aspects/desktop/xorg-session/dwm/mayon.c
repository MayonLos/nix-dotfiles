/* Local barmodules and behavior for the pinned flexipatch source.
 * Clock is allocated before either side: it stays at the monitor center.
 * The bar allocator clips left titles / right status independently on small outputs.
 */
static int
mayonmatch(const char *pattern, const char *text)
{
	regex_t regex;
	int matched;
	if (!pattern) return 1;
	if (regcomp(&regex, pattern, REG_EXTENDED | REG_NOSUB) != 0) return 0;
	matched = regexec(&regex, text, 0, NULL, 0) == 0;
	regfree(&regex);
	return matched;
}

static void
mayonclocktext(char *text, size_t size)
{
	if (!gettextprop(root, XInternAtom(dpy, "_MAYON_DWM_CLOCK", False), text, size))
		snprintf(text, size, "dwm · Xorg");
}

static int
width_mayonclock(Bar *bar, BarArg *a)
{
	char text[128];
	mayonclocktext(text, sizeof text);
	return MIN(TEXTW(text) + lrpad, a->w / 3);
}

static int
draw_mayonclock(Bar *bar, BarArg *a)
{
	char text[128];
	mayonclocktext(text, sizeof text);
	drw_setscheme(drw, scheme[SchemeNorm]);
	drw_text(drw, a->x, a->y, a->w, a->h, lrpad, text, 0, False);
	return 1;
}

/* status2d's upstream painter ignores a->w. On a narrow output use its
 * plain text with native ellipsis, preserving the clock and tray allocations. */
static int
draw_mayonstatus(Bar *bar, BarArg *a)
{
	char plain[1024];
	size_t i, n = 0;
	int code = 0;
	if (a->w <= 0) return 1;
	if (status2dtextlength(stext) <= a->w)
		return draw_status2d(bar, a);
	for (i = 0; stext[i] && n < sizeof plain - 1; i++) {
		if (stext[i] == '^') { code = !code; continue; }
		if (!code) plain[n++] = stext[i];
	}
	plain[n] = '\0';
	drw_setscheme(drw, scheme[SchemeNorm]);
	drw_text(drw, a->x, a->y, a->w, a->h, 0, plain, 0, False);
	return 1;
}

static int
width_mayonsep(Bar *bar, BarArg *a)
{
	return lrpad;
}

static int
draw_mayonsep(Bar *bar, BarArg *a)
{
	drw_setscheme(drw, scheme[SchemeTagsNorm]);
	XSetForeground(dpy, drw->gc, scheme[SchemeNorm][ColBorder].pixel);
	XFillRectangle(dpy, drw->drawable, drw->gc, a->x + a->w / 2,
	               a->y + a->h / 4, 1, a->h / 2);
	return 1;
}

static void
mayontagfollow(const Arg *arg)
{
	Client *c = selmon->sel;
	if (!c) return;
	tag(arg);
	view(arg);
	focus(c);
	restack(selmon);
}

/* SAVEFLOATS_PATCH makes the Float layout restore these cached coordinates
 * from showhide(). Keep direct geometry changes in step with that cache. */
static void
mayonsavefloat(Client *c)
{
	c->sfx = c->x;
	c->sfy = c->y;
	c->sfw = c->w;
	c->sfh = c->h;
}

static int
mayonfloatlayout(Client *c)
{
	return !c->mon->lt[c->mon->sellt]->arrange;
}

static void
mayoncenter(const Arg *arg)
{
	Client *c = selmon->sel;
	if (!c || c->isfullscreen) return;
	if (!c->isfloating) togglefloating(NULL);
	resize(c, c->mon->wx + (c->mon->ww - WIDTH(c)) / 2,
	       c->mon->wy + (c->mon->wh - HEIGHT(c)) / 2, c->w, c->h, 1);
	mayonsavefloat(c);
}

static void
mayonmaximize(const Arg *arg)
{
	Client *c = selmon->sel;
	if (!c || c->isfullscreen) return;
	if (!c->mayonmax) {
		c->mayonoldfloat = c->isfloating;
		c->mayonx = c->x; c->mayony = c->y;
		c->mayonw = c->w; c->mayonh = c->h;
		c->isfloating = 1;
		resize(c, c->mon->wx, c->mon->wy,
		       c->mon->ww - 2 * c->bw, c->mon->wh - 2 * c->bw, 1);
		mayonsavefloat(c);
		c->mayonmax = 1;
	} else {
		c->isfloating = c->mayonoldfloat;
		resize(c, c->mayonx, c->mayony, c->mayonw, c->mayonh, 1);
		mayonsavefloat(c);
		c->mayonmax = 0;
	}
	updatefloatingproperty(c);
	arrange(c->mon);
}

static void
mayonmove(const Arg *arg)
{
	Client *s = selmon->sel, *target, **sp, **tp, *sn, *tn;
	if (!s || s->isfullscreen) return;
	if (s->isfloating || mayonfloatlayout(s)) {
		int step = bh;
		resize(s, s->x + (arg->i == 0 ? -step : arg->i == 1 ? step : 0),
		       s->y + (arg->i == 2 ? -step : arg->i == 3 ? step : 0), s->w, s->h, 1);
		mayonsavefloat(s);
		return;
	}
	focusdir(arg);
	target = selmon->sel;
	if (!target || target == s) return;
	for (sp = &selmon->clients; *sp && *sp != s; sp = &(*sp)->next);
	for (tp = &selmon->clients; *tp && *tp != target; tp = &(*tp)->next);
	sn = s->next; tn = target->next;
	if (sn == target) { *sp = target; target->next = s; s->next = tn; }
	else if (tn == s) { *tp = s; s->next = target; target->next = sn; }
	else { *sp = target; *tp = s; s->next = tn; target->next = sn; }
	focus(s);
	arrange(selmon);
}
