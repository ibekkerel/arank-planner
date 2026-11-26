import Foundation

@main struct WorkspaceFilterCheck {
    static func main() {
        let p = Schedule(name:"test",activities:[
            Activity(id:"root",name:"Основная группа",duration:0,kind:"summary"),
            Activity(id:"grp-a",name:"Первая группа",duration:0,kind:"summary",parent:"root"),
            Activity(id:"x",name:"Планёрный этап",duration:2,progress:99,kind:"task",parent:"grp-a"),
            Activity(id:"grp-b",name:"Вторая группа",duration:0,kind:"summary",parent:"root"),
            Activity(id:"y",name:"Передача чертежей",duration:0,kind:"milestone",parent:"grp-b"),
            Activity(id:"z",name:"Полезная работа",duration:3,progress:100,kind:"task"),
        ],links:[],resources:[])
        let ordered = p.orderedActivities
        let all = WorkFilter.all.rows(ordered,terms:[],collapsed:["root"],timings:[:])
        precondition(all.map(\.activity.id) == ["root","z"])
        let search = WorkFilter.all.rows(ordered,terms:WorkFilter.terms("  y ЧеРТеЖеЙ "),collapsed:["root"],timings:[:])
        precondition(search.map(\.activity.id) == ["root","grp-b","y"])
        precondition(search.map(\.contextOnly) == [true,true,false])
        let progress = WorkFilter.inProgress.rows(ordered,terms:WorkFilter.terms("планерный"),collapsed:[],timings:[:])
        precondition(progress.map(\.activity.id) == ["root","grp-a","x"])
        let incomplete = WorkFilter.unfinished.rows(ordered,terms:[],collapsed:[],timings:[:])
        precondition(incomplete.map(\.activity.id) == ["root","grp-a","x"])
        let milestone = WorkFilter.milestones.rows(ordered,terms:[],collapsed:[],timings:[:])
        precondition(milestone.map(\.activity.id) == ["root","grp-b","y"])
        let critical = WorkFilter.critical.rows(ordered,terms:[],collapsed:[],timings:["x":Timing(start:0,finish:2,lateStart:0,float:0),"y":Timing(start:4,finish:4,lateStart:6,float:2)])
        precondition(critical.map(\.activity.id) == ["root","grp-a","x"])
        precondition(WorkFilter.critical.rows(ordered,terms:[],collapsed:[],timings:[:]).isEmpty)
        print("Planner workspace filter fixtures passed")
    }
}
