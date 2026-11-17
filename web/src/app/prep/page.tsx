import { prisma } from "@/lib/db";
import { pageContext } from "@/lib/page";

interface PrepStep { id: string; title: string; detail?: string; lane: string; minutes: number; timerMinutes?: number; recipeNames: string[]; group: number }

export default async function PrepPage() {
  const { household } = await pageContext();
  const sessions = await prisma.prepSession.findMany({ where: { householdId: household.id }, orderBy: { date: "desc" }, take: 5, include: { batches: true } });
  const batches = await prisma.prepBatch.findMany({ where: { householdId: household.id, portionsLeft: { gt: 0 } }, orderBy: { expiryDate: "asc" } });
  return (
    <>
      <h1>Prep</h1>
      <p className="lede">Prep sessions are run from the iOS app (timers, parallel steps, portioning). This page shows what was made and what's left.</p>
      <h2>Portions on hand</h2>
      <div className="card">
        {batches.map((b) => <div key={b.id} className="row"><span className="grow">{b.name} <span className="muted">· {b.container || "container"} · {b.storage}</span></span><span className="badge green">{b.portionsLeft} / {b.portions} left</span><span className="muted">until {b.expiryDate.toLocaleDateString()}</span></div>)}
        {batches.length === 0 ? <p className="muted">No prepped portions right now.</p> : null}
      </div>
      {sessions.map((session) => {
        const plan = session.plan as unknown as { steps: PrepStep[]; estimatedMinutes: number };
        const groups = new Map<number, PrepStep[]>();
        for (const step of plan.steps ?? []) groups.set(step.group, [...(groups.get(step.group) ?? []), step]);
        return (
          <div key={session.id} className="card" style={{ marginTop: 12 }}>
            <h2 style={{ marginTop: 0 }}>{session.title || "Prep session"} <span className="badge accent">{session.isCompleted ? "done" : "in progress"}</span> <span className="muted">~{plan.estimatedMinutes} min</span></h2>
            {[...groups.entries()].map(([group, steps]) => (
              <div key={group} style={{ marginBottom: 8 }}>
                <div className="muted">{steps.length > 1 ? "At the same time" : "Next"}</div>
                {steps.map((step) => <div key={step.id} className="step"><span className="n">{step.lane[0].toUpperCase()}</span><span className={session.completedStepIds.includes(step.id) ? "checked" : ""}>{step.title}{step.timerMinutes ? <span className="muted"> · {step.timerMinutes} min timer</span> : null}</span></div>)}
              </div>
            ))}
          </div>
        );
      })}
    </>
  );
}
