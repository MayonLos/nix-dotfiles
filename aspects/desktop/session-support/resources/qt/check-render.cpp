#include <QApplication>
#include <QCheckBox>
#include <QFile>
#include <QGroupBox>
#include <QImage>
#include <QPainter>
#include <QRadioButton>
#include <QStyle>
#include <QStyleOptionButton>
#include <QStyleOptionGroupBox>
#include <QDebug>
#include <cstdlib>

class CheckBoxProbe : public QCheckBox {
public:
    using QCheckBox::QCheckBox;
    QRect indicatorRect() const {
        QStyleOptionButton option;
        initStyleOption(&option);
        return style()->subElementRect(QStyle::SE_CheckBoxIndicator, &option, this);
    }
};

class RadioButtonProbe : public QRadioButton {
public:
    using QRadioButton::QRadioButton;
    QRect indicatorRect() const {
        QStyleOptionButton option;
        initStyleOption(&option);
        return style()->subElementRect(QStyle::SE_RadioButtonIndicator, &option, this);
    }
};

class GroupBoxProbe : public QGroupBox {
public:
    using QGroupBox::QGroupBox;
    QRect indicatorRect() const {
        QStyleOptionGroupBox option;
        initStyleOption(&option);
        return style()->subControlRect(QStyle::CC_GroupBox, &option, QStyle::SC_GroupBoxCheckBox, this);
    }
};

template<class Widget>
int countColor(const QImage& image, const Widget* widget, QColor color) {
    const QPoint center = widget->mapTo(widget->window(), widget->indicatorRect().center());
    int count = 0;
    for (int y = center.y() - 8; y <= center.y() + 8; ++y)
        for (int x = center.x() - 8; x <= center.x() + 8; ++x)
            if (image.rect().contains(x, y) && image.pixelColor(x, y) == color)
                ++count;
    return count;
}

template<class Widget>
int countNearColor(const QImage& image, const Widget* widget, QColor color, int tolerance) {
    const QPoint center = widget->mapTo(widget->window(), widget->indicatorRect().center());
    int count = 0;
    for (int y = center.y() - 8; y <= center.y() + 8; ++y)
        for (int x = center.x() - 8; x <= center.x() + 8; ++x) {
            if (!image.rect().contains(x, y)) continue;
            const QColor actual = image.pixelColor(x, y);
            const int distance = std::abs(actual.red() - color.red()) + std::abs(actual.green() - color.green()) +
              std::abs(actual.blue() - color.blue());
            if (distance <= tolerance) ++count;
        }
    return count;
}

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    QApplication app(argc, argv);
    QApplication::setStyle(QStringLiteral("Fusion"));

    QFile qssFile(QString::fromLocal8Bit(argv[1]));
    if (!qssFile.open(QIODevice::ReadOnly)) return 3;
    app.setStyleSheet(QString::fromUtf8(qssFile.readAll()));

    QWidget canvas;
    canvas.resize(520, 290);
    canvas.setAutoFillBackground(true);
    QPalette palette = canvas.palette();
    palette.setColor(QPalette::Window, QColor("#1e2228"));
    palette.setColor(QPalette::WindowText, QColor("#d7dae0"));
    palette.setColor(QPalette::Text, QColor("#d7dae0"));
    palette.setColor(QPalette::Base, QColor("#181b20"));
    canvas.setPalette(palette);

    GroupBoxProbe group(QStringLiteral("Performance"), &canvas);
    group.setCheckable(true);
    group.setChecked(true);
    group.setGeometry(10, 10, 500, 260);

    CheckBoxProbe checked(QStringLiteral("Checked"), &group);
    checked.setGeometry(22, 42, 210, 24);
    checked.setChecked(true);
    CheckBoxProbe unchecked(QStringLiteral("Unchecked"), &group);
    unchecked.setGeometry(22, 76, 210, 24);
    CheckBoxProbe mixed(QStringLiteral("Mixed"), &group);
    mixed.setGeometry(22, 110, 210, 24);
    mixed.setTristate(true);
    mixed.setCheckState(Qt::PartiallyChecked);
    CheckBoxProbe disabledMixed(QStringLiteral("Disabled mixed"), &group);
    disabledMixed.setGeometry(22, 144, 210, 24);
    disabledMixed.setTristate(true);
    disabledMixed.setCheckState(Qt::PartiallyChecked);
    disabledMixed.setEnabled(false);
    CheckBoxProbe disabledChecked(QStringLiteral("Disabled checked"), &group);
    disabledChecked.setGeometry(252, 42, 220, 24);
    disabledChecked.setChecked(true);
    disabledChecked.setEnabled(false);
    CheckBoxProbe disabledUnchecked(QStringLiteral("Disabled unchecked"), &group);
    disabledUnchecked.setGeometry(252, 76, 220, 24);
    disabledUnchecked.setEnabled(false);

    RadioButtonProbe radioChecked(QStringLiteral("Radio checked"), &group);
    radioChecked.setGeometry(22, 188, 210, 24);
    radioChecked.setAutoExclusive(false);
    radioChecked.setChecked(true);
    RadioButtonProbe radioDisabledChecked(QStringLiteral("Radio disabled"), &group);
    radioDisabledChecked.setGeometry(252, 110, 220, 24);
    radioDisabledChecked.setAutoExclusive(false);
    radioDisabledChecked.setChecked(true);
    radioDisabledChecked.setEnabled(false);

    canvas.show();
    app.processEvents();
    canvas.setFocus();
    app.processEvents();
    QImage image(canvas.size(), QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    canvas.render(&image);
    if (!image.save(QString::fromLocal8Bit(argv[2]))) return 4;

    const QColor blue("#61afef");
    const QColor deep("#181b20");
    const QColor selection("#323843");
    const QColor surface("#272c33");
    const QColor bg("#1e2228");
    const int checkedBlue = countColor(image, &checked, blue);
    const int uncheckedBlue = countColor(image, &unchecked, blue);
    const QPoint uncheckedCenter = unchecked.mapTo(unchecked.window(), unchecked.indicatorRect().center());
    const QColor uncheckedFill = image.pixelColor(uncheckedCenter);
    const int mixedSelection = countColor(image, &mixed, selection);
    const int mixedMuted = countNearColor(image, &disabledMixed, QColor("#828a95"), 32);
    const int disabledSelection = countColor(image, &disabledChecked, selection);
    const QPoint disabledUncheckedCenter = disabledUnchecked.mapTo(
      disabledUnchecked.window(), disabledUnchecked.indicatorRect().center());
    const QColor disabledUncheckedFill = image.pixelColor(disabledUncheckedCenter);
    const QPoint radioCenter = radioChecked.mapTo(radioChecked.window(), radioChecked.indicatorRect().center());
    const QColor radioFill = image.pixelColor(radioCenter);
    const QPoint radioDisabledCenter = radioDisabledChecked.mapTo(
      radioDisabledChecked.window(), radioDisabledChecked.indicatorRect().center());
    const int radioDisabledSelection = countColor(image, &radioDisabledChecked, selection);
    const QColor radioDisabledFill = image.pixelColor(radioDisabledCenter);
    const bool radioSizesMatch = radioChecked.indicatorRect().size() == radioDisabledChecked.indicatorRect().size();
    const int groupBlue = countColor(image, &group, blue);
    const QColor groupFill = image.pixelColor(480, 240);

    if (checkedBlue < 20 || uncheckedBlue != 0 || uncheckedFill != deep || mixedSelection < 20 || mixedMuted < 8 ||
        disabledSelection < 20 || disabledUncheckedFill != surface ||
        radioFill != blue || radioDisabledSelection < 6 || radioDisabledFill != QColor("#828a95") || !radioSizesMatch ||
        groupBlue < 20 || groupFill != bg) {
        qWarning() << "indicator pixels checked/unchecked/mixed/disabled/radio/group:"
                   << checkedBlue << uncheckedBlue << uncheckedFill << mixedSelection << mixedMuted << disabledSelection
                   << disabledUncheckedFill << radioFill << radioDisabledSelection << radioDisabledFill << radioSizesMatch << groupBlue
                   << "group fill:" << groupFill;
        return 1;
    }
    qInfo() << "One Dark Qt render state matrix passed; group fill:" << groupFill;
    return 0;
}
