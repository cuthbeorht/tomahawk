#ifndef PROXYSTYLE_H
#define PROXYSTYLE_H

#include <QtGlobal>
#include <QProxyStyle>

class ProxyStyle : public QProxyStyle
{
public:
    ProxyStyle() {}

    virtual void drawPrimitive( PrimitiveElement pe, const QStyleOption *opt, QPainter *p, const QWidget *w = 0 ) const;
};

#endif // PROXYSTYLE_H
