/* Tags keep the upstream hit boxes. Dots mean occupied; lines mean active/urgent. */
int
width_tags(Bar *bar, BarArg *a)
{
	unsigned int i;
	int w = 0;
	for (i = 0; i < NUMTAGS; i++) w += TEXTW(tagicon(bar->mon, i));
	return w;
}

int
draw_tags(Bar *bar, BarArg *a)
{
	unsigned int i, occ = 0, urg = 0;
	int x = a->x, w, active, line = MAX(2, a->h / 15), dot = MAX(3, a->h / 12);
	Monitor *m = bar->mon;
	Client *c;
	for (c = m->clients; c; c = c->next) {
		occ |= c->tags;
		if (c->isurgent) urg |= c->tags;
	}
	for (i = 0; i < NUMTAGS; i++) {
		w = TEXTW(tagicon(m, i));
		if (x + w > a->x + a->w) break;
		active = !!(m->tagset[m->seltags] & 1 << i);
		drw_setscheme(drw, scheme[active ? SchemeTagsSel : urg & 1 << i ? SchemeUrg : SchemeTagsNorm]);
		drw_text(drw, x, a->y, w, a->h, lrpad / 2, tagicon(m, i), 0, False);
		if (active || urg & 1 << i) {
			XSetForeground(dpy, drw->gc, scheme[urg & 1 << i ? SchemeUrg : SchemeSel][ColFg].pixel);
			XFillRectangle(dpy, drw->drawable, drw->gc, x + ulinepad,
			               a->y + a->h - line - 2, MAX(1, w - 2 * ulinepad), line);
		} else if (occ & 1 << i) {
			XSetForeground(dpy, drw->gc, scheme[SchemeTagsNorm][ColFg].pixel);
			XFillArc(dpy, drw->drawable, drw->gc, x + (w-dot)/2,
			         a->y + a->h - dot - 2, dot, dot, 0, 360 * 64);
		}
		x += w;
	}
	return 1;
}

int
click_tags(Bar *bar, Arg *arg, BarArg *a)
{
	unsigned int i;
	int x = 0;
	for (i = 0; i < NUMTAGS; i++) {
		x += TEXTW(tagicon(bar->mon, i));
		if (a->x < x) { arg->ui = 1 << i; break; }
	}
	return ClkTagBar;
}

int
hover_tags(Bar *bar, BarArg *a, XMotionEvent *ev)
{
	return 1;
}
