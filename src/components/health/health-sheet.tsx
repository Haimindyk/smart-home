"use client";
import type { ReactNode } from "react";
import { X } from "lucide-react";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useHealthText } from "@/lib/health/i18n";

export function HealthSheet({
  title,
  onClose,
  children,
  action,
  className = "",
  closeDisabled = false,
  blurOverlay = true,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
  action?: ReactNode;
  className?: string;
  closeDisabled?: boolean;
  blurOverlay?: boolean;
}) {
  const h = useHealthText();
  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open && !closeDisabled) onClose();
      }}
    >
      <DialogContent
        className={`health-app health-editor-sheet start-0 top-auto bottom-0 translate-x-0 translate-y-0 rtl:translate-x-0 ${className}`}
        blurOverlay={blurOverlay}
        showCloseButton={false}
      >
        <div className="health-sheet-heading">
          <span className="health-sheet-handle" aria-hidden="true" />
          <div>
            {action && <span className="health-sheet-action">{action}</span>}
            <DialogTitle style={{ fontFamily: "inherit" }}>{title}</DialogTitle>
            <Button
              variant="ghost"
              onClick={onClose}
              disabled={closeDisabled}
              aria-label={h("סגירה", "Close")}
            >
              <X size={21} />
            </Button>
          </div>
        </div>
        <div className="health-sheet-body">{children}</div>
      </DialogContent>
    </Dialog>
  );
}
