import QtQuick 2.0
import Machinekit.Application 1.0
import Machinekit.Application.Controls 1.0
import Machinekit.Service 1.0
import "./Cetus"

Item {
    id: connectionWindow
    width: 1200
    height: 1000
    
    property string title: "Cetus"
    property alias toolBar: cetus.toolBar
    property alias statusBar: cetus.statusBar
    property alias menuBar: cetus.menuBar
    
    ApplicationDescription {
        sourceDir: "./Cetus/"
    }
    
    Cetus {
        id: cetus
        anchors.fill: parent
    }
}
